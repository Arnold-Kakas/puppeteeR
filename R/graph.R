#' Sentinel: start of graph
#'
#' Use `START` as the `from` argument of [add_edge()] to define the graph
#' entry point.
#'
#' @export
START <- structure("__START__", class = "puppeteer_sentinel")

#' Sentinel: end of graph
#'
#' Use `END` as the `to` argument of [add_edge()] or in a `route_map` to
#' indicate that execution should stop.
#'
#' @export
END <- structure("__END__", class = "puppeteer_sentinel")

#' StateGraph R6 class
#'
#' @description
#' Builder for directed graphs of node functions. Nodes are named R functions;
#' edges are fixed or conditional routing rules. Call `$compile()` to produce
#' an executable [GraphRunner].
#'
#' Use the pipe-friendly wrappers [add_node()], [add_edge()], and
#' [add_conditional_edge()] rather than `$`-methods directly.
#'
#' @export
StateGraph <- R6::R6Class(
  "StateGraph",
  public = list(

    #' @description Create a new StateGraph.
    #' @param state_schema A [WorkflowState] object, or a named list that will
    #'   be passed to [workflow_state()].
    #' @returns A new `StateGraph` object.
    initialize = function(state_schema) {
      rlang::check_required(state_schema)
      if (!inherits(state_schema, "WorkflowState")) {
        state_schema <- do.call(workflow_state, state_schema)
      }
      private$.state_schema <- state_schema
    },

    #' @description Register a node function.
    #' @param name Character. Unique node name.
    #' @param fn Function with signature `function(state, config)` returning a
    #'   named list of state updates.
    #' @param retry A [retry_policy()] object or `NULL`. When non-`NULL`, the
    #'   runner retries the node on error according to the policy.
    #' @returns Invisibly, `self` (for chaining with `|>`).
    add_node = function(name, fn, retry = NULL) {
      check_node_name(name, nodes = NULL, allow_sentinel = FALSE)
      check_is_function(fn)
      check_is_retry_policy(retry)
      if (name %in% names(private$.nodes)) {
        cli::cli_abort("A node named {.val {name}} already exists.")
      }
      private$.nodes[[name]] <- list(fn = fn, retry = retry)
      invisible(self)
    },

    #' @description Add a fixed edge between two nodes.
    #' @param from Node name or [START].
    #' @param to Node name or [END].
    #' @returns Invisibly, `self`.
    add_edge = function(from, to) {
      check_node_name(from, private$.nodes, allow_sentinel = TRUE)
      check_node_name(to, private$.nodes, allow_sentinel = TRUE)

      from_id <- sentinel_id(from)
      existing_fixed <- vapply(
        private$.edges, function(e) sentinel_id(e$from) == from_id, logical(1)
      )
      if (any(existing_fixed)) {
        cli::cli_abort(
          "Node {.val {from_id}} already has a fixed outgoing edge. \\
           Use {.fn add_conditional_edge} for multiple targets."
        )
      }

      private$.edges <- c(private$.edges, list(list(from = from, to = to)))
      invisible(self)
    },

    #' @description Add a conditional (routing) edge.
    #' @param from Node name. Must already be registered.
    #' @param routing_fn Function `function(state)` returning a character key
    #'   present in `route_map`.
    #' @param route_map Named list mapping routing keys to node names or [END].
    #' @returns Invisibly, `self`.
    add_conditional_edge = function(from, routing_fn, route_map) {
      check_node_name(from, private$.nodes, allow_sentinel = FALSE)
      check_is_function(routing_fn, "routing_fn")
      check_named_list(route_map, "route_map")

      for (target in route_map) {
        check_node_name(target, private$.nodes, allow_sentinel = TRUE)
      }

      from_id <- sentinel_id(from)
      existing_cond <- vapply(
        private$.conditional_edges,
        function(e) sentinel_id(e$from) == from_id,
        logical(1)
      )
      if (any(existing_cond)) {
        cli::cli_abort("Node {.val {from_id}} already has a conditional edge.")
      }

      private$.conditional_edges <- c(
        private$.conditional_edges,
        list(list(from = from, routing_fn = routing_fn, route_map = route_map))
      )
      invisible(self)
    },

    #' @description Shortcut to set the graph entry node.
    #' @param name Character. Must be a registered node.
    #' @returns Invisibly, `self`.
    set_entry = function(name) {
      self$add_edge(START, name)
    },

    #' @description Validate and compile the graph into a [GraphRunner].
    #' @param agents Named list of `Agent` objects passed to node functions via
    #'   `config$agents`.
    #' @param checkpointer A [Checkpointer] object or `NULL`. Required when
    #'   `interrupt_before` or `interrupt_after` is non-empty.
    #' @param termination A termination condition (from [max_turns()] etc.) or
    #'   `NULL`.
    #' @param output_channel Character or `NULL`. The channel whose value is
    #'   returned by `WorkflowState$output()`. If `NULL`, `$output()` will
    #'   error unless set by a workflow constructor.
    #' @param interrupt_before Character vector of node names. Execution pauses
    #'   **before** each listed node and returns control to the caller.
    #' @param interrupt_after Character vector of node names. Execution pauses
    #'   **after** each listed node and returns control to the caller.
    #' @returns A [GraphRunner] object ready to execute.
    compile = function(agents = list(), checkpointer = NULL, termination = NULL,
                       output_channel = NULL,
                       interrupt_before = character(), interrupt_after = character()) {
      private$.validate(has_termination = !is.null(termination))

      if (length(interrupt_before) > 0L || length(interrupt_after) > 0L) {
        if (is.null(checkpointer)) {
          cli::cli_abort(
            "A {.cls Checkpointer} is required when {.arg interrupt_before} or \\
             {.arg interrupt_after} is set."
          )
        }
        unknown_before <- setdiff(interrupt_before, names(private$.nodes))
        if (length(unknown_before) > 0L) {
          cli::cli_abort(
            "{.arg interrupt_before} contains unknown node(s): {.val {unknown_before}}."
          )
        }
        unknown_after <- setdiff(interrupt_after, names(private$.nodes))
        if (length(unknown_after) > 0L) {
          cli::cli_abort(
            "{.arg interrupt_after} contains unknown node(s): {.val {unknown_after}}."
          )
        }
      }

      GraphRunner$new(
        nodes             = private$.nodes,
        edges             = private$.edges,
        conditional_edges = private$.conditional_edges,
        state_schema      = private$.state_schema$schema,
        agents            = agents,
        checkpointer      = checkpointer,
        termination       = termination,
        output_channel    = output_channel,
        interrupt_before  = interrupt_before,
        interrupt_after   = interrupt_after
      )
    },

    #' @description Generate a DOT language string for the graph.
    #' @returns Character string.
    as_dot = function() {
      graph_as_dot(self, private$.nodes, private$.edges, private$.conditional_edges)
    },

    #' @description Generate a Mermaid diagram string.
    #' @returns Character string.
    as_mermaid = function() {
      graph_as_mermaid(self, private$.nodes, private$.edges, private$.conditional_edges)
    },

    #' @description Render a visualization.
    #' @param engine One of `"dot"`, `"visnetwork"`, or `"mermaid"`.
    visualize = function(engine = c("dot", "visnetwork", "mermaid")) {
      engine <- rlang::arg_match(engine)
      visualize_graph(self, engine)
    },

    #' @description Export the diagram to a file.
    #' @param path File path. Extension determines format (`.svg` or `.png`).
    #' @param width Integer. Width in pixels (PNG only).
    #' @param height Integer. Height in pixels (PNG only).
    #' @returns Invisibly, `path`.
    export_diagram = function(path, width = 800L, height = 600L) {
      export_diagram_impl(self, path, width, height)
    },

    #' @description Print graph summary.
    #' @param ... Ignored.
    print = function(...) {
      n_nodes <- length(private$.nodes)
      n_edges <- length(private$.edges) + length(private$.conditional_edges)
      cli::cli_inform(c(
        "!" = "StateGraph",
        " " = "Nodes ({n_nodes}): {.val {names(private$.nodes)}}",
        " " = "Edges: {n_edges} total ({length(private$.edges)} fixed, \\
               {length(private$.conditional_edges)} conditional)"
      ))
      invisible(self)
    }
  ),

  private = list(
    .nodes = list(),
    .edges = list(),
    .conditional_edges = list(),
    .state_schema = NULL,

    .validate = function(has_termination = FALSE) {
      if (length(private$.nodes) == 0L) {
        cli::cli_abort("Graph has no nodes. Use {.fn add_node} first.")
      }

      start_edges <- Filter(
        function(e) is_sentinel(e$from) && as.character(e$from) == "__START__",
        private$.edges
      )
      if (length(start_edges) != 1L) {
        cli::cli_abort(
          "Graph must have exactly one edge from {.code START}. \\
           Found {length(start_edges)}."
        )
      }

      has_end_edge <- function(edges) {
        any(vapply(edges, function(e) {
          is_sentinel(e$to) && as.character(e$to) == "__END__"
        }, logical(1)))
      }
      has_end_cond <- function(cond_edges) {
        any(vapply(cond_edges, function(ce) {
          any(vapply(ce$route_map, function(t) {
            is_sentinel(t) && as.character(t) == "__END__"
          }, logical(1)))
        }, logical(1)))
      }
      if (!has_termination &&
          !has_end_edge(private$.edges) &&
          !has_end_cond(private$.conditional_edges)) {
        cli::cli_abort(
          "Graph must have at least one path to {.code END}, \\
           or supply a {.arg termination} condition to {.fn compile}."
        )
      }

      for (node_name in names(private$.nodes)) {
        fixed_out <- any(vapply(
          private$.edges,
          function(e) !is_sentinel(e$from) && e$from == node_name,
          logical(1)
        ))
        cond_out <- any(vapply(
          private$.conditional_edges,
          function(e) e$from == node_name,
          logical(1)
        ))
        if (fixed_out && cond_out) {
          cli::cli_abort(
            "Node {.val {node_name}} has both a fixed edge and a conditional edge. \\
             Only one outgoing edge type is allowed per node."
          )
        }
      }
    }
  )
)

#' Create a StateGraph
#'
#' @param state_schema A [WorkflowState] or a named list of channel specs.
#' @returns A [StateGraph] object.
#' @export
#' @examples
#' schema <- workflow_state(result = list(default = NULL))
#' g <- state_graph(schema)
state_graph <- function(state_schema) {
  if (!inherits(state_schema, "WorkflowState")) {
    state_schema <- do.call(workflow_state, state_schema)
  }
  StateGraph$new(state_schema)
}

#' Add a node to a graph
#'
#' @param graph A [StateGraph] object.
#' @param name Character. Unique node name.
#' @param fn Function `function(state, config)` returning a named list of
#'   state updates.
#' @param retry A [retry_policy()] object or `NULL`. When non-`NULL`, the
#'   runner retries the node on error according to the policy.
#' @returns `graph`, invisibly (for `|>` chaining).
#' @export
#' @examples
#' schema <- workflow_state(result = list(default = NULL))
#' g <- state_graph(schema) |>
#'   add_node("step1", function(state, config) list(result = "done"))
add_node <- function(graph, name, fn, retry = NULL) {
  graph$add_node(name, fn, retry = retry)
}

#' Add a fixed edge to a graph
#'
#' @param graph A [StateGraph] object.
#' @param from Node name or [START].
#' @param to Node name or [END].
#' @returns `graph`, invisibly.
#' @export
#' @examples
#' schema <- workflow_state(result = list(default = NULL))
#' g <- state_graph(schema) |>
#'   add_node("step1", function(state, config) list(result = "done")) |>
#'   add_edge(START, "step1") |>
#'   add_edge("step1", END)
add_edge <- function(graph, from, to) {
  graph$add_edge(from, to)
}

#' Compile a StateGraph into a GraphRunner
#'
#' @param graph A [StateGraph] object.
#' @param agents Named list of `Agent` objects.
#' @param checkpointer A [Checkpointer] or `NULL`. Required when
#'   `interrupt_before` or `interrupt_after` is non-empty.
#' @param termination A termination condition or `NULL`.
#' @param output_channel Character or `NULL`. Channel returned by
#'   `WorkflowState$output()` after `$invoke()`.
#' @param interrupt_before Character vector of node names. Execution pauses
#'   before each listed node and returns control to the caller. Requires a
#'   checkpointer and a `thread_id` in `config`.
#' @param interrupt_after Character vector of node names. Execution pauses
#'   after each listed node and returns control to the caller. Requires a
#'   checkpointer and a `thread_id` in `config`.
#' @returns A [GraphRunner] object.
#' @export
#' @examples
#' schema <- workflow_state(result = list(default = NULL))
#' runner <- state_graph(schema) |>
#'   add_node("step1", function(state, config) list(result = "done")) |>
#'   add_edge(START, "step1") |>
#'   add_edge("step1", END) |>
#'   compile(output_channel = "result")
compile <- function(graph, agents = list(), checkpointer = NULL, termination = NULL,
                    output_channel = NULL,
                    interrupt_before = character(), interrupt_after = character()) {
  graph$compile(agents = agents, checkpointer = checkpointer, termination = termination,
                output_channel = output_channel,
                interrupt_before = interrupt_before, interrupt_after = interrupt_after)
}

#' Add a conditional edge to a graph
#'
#' @param graph A [StateGraph] object.
#' @param from Character. Source node name.
#' @param routing_fn Function `function(state)` returning a key in `route_map`.
#' @param route_map Named list mapping routing keys to target node names or
#'   [END].
#' @returns `graph`, invisibly.
#' @export
#' @examples
#' schema <- workflow_state(
#'   value = list(default = 0L),
#'   result = list(default = NULL)
#' )
#' g <- state_graph(schema) |>
#'   add_node("check", function(state, config) list()) |>
#'   add_node("high",  function(state, config) list(result = "high")) |>
#'   add_node("low",   function(state, config) list(result = "low")) |>
#'   add_edge(START, "check") |>
#'   add_conditional_edge(
#'     "check",
#'     routing_fn  = function(state) if (state$get("value") > 5L) "hi" else "lo",
#'     route_map   = list(hi = "high", lo = "low")
#'   ) |>
#'   add_edge("high", END) |>
#'   add_edge("low",  END)
add_conditional_edge <- function(graph, from, routing_fn, route_map) {
  graph$add_conditional_edge(from, routing_fn, route_map)
}
