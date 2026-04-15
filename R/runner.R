#' GraphRunner R6 class
#'
#' @description
#' The compiled, executable graph. Produced by [StateGraph]`$compile()`. Do not
#' call `GraphRunner$new()` directly; use [StateGraph]`$compile()`.
#'
#' @export
GraphRunner <- R6::R6Class(
  "GraphRunner",
  public = list(

    #' @description Initialise the runner. Called internally by `StateGraph$compile()`.
    #' @param nodes Named list of `list(fn = <function>)`.
    #' @param edges List of `list(from, to)`.
    #' @param conditional_edges List of `list(from, routing_fn, route_map)`.
    #' @param state_schema A [WorkflowState] object (used as schema template).
    #' @param agents Named list of `Agent` objects.
    #' @param checkpointer A [Checkpointer] or `NULL`.
    #' @param termination A `termination_condition` or `NULL`.
    #' @param output_channel Character or `NULL`. Name of the channel returned
    #'   by `WorkflowState$output()` after `$invoke()`.
    initialize = function(nodes, edges, conditional_edges,
                          state_schema, agents, checkpointer, termination,
                          output_channel = NULL) {
      private$.nodes             <- nodes
      private$.edges             <- edges
      private$.conditional_edges <- conditional_edges
      private$.state_schema      <- state_schema
      private$.agents            <- agents
      private$.checkpointer      <- checkpointer
      private$.termination       <- termination
      private$.output_channel    <- output_channel
      private$.adjacency         <- private$.build_adjacency()
    },

    #' @description Execute the graph and return the final state.
    #' @param initial_state Named list of initial channel overrides.
    #' @param config Named list of run-time configuration:
    #'   - `thread_id`: character, identifies this run for checkpointing.
    #'   - `max_iterations`: integer, cycle guard (default 25).
    #'   - `on_step`: `function(node_name, state)` callback after each node.
    #'   - `verbose`: logical, print step info via `cli` (default `FALSE`).
    #' @returns The final [WorkflowState] object.
    invoke = function(initial_state = list(), config = list()) {
      state <- private$.init_state(initial_state)
      config <- private$.enrich_config(config)

      thread_id      <- config$thread_id
      max_iter       <- config$max_iterations %||% 25L
      on_step        <- config$on_step
      verbose        <- isTRUE(config$verbose)

      start_step <- 0L
      if (!is.null(private$.checkpointer) && !is.null(thread_id)) {
        saved <- private$.checkpointer$load_latest(thread_id)
        if (!is.null(saved)) {
          state$restore(saved$state)
          start_step <- saved$step
          if (verbose) {
            cli::cli_inform("Resuming from checkpoint at step {start_step}.")
          }
        }
      }

      entry <- private$.entry_node()
      current_node <- entry

      for (iter in seq_len(max_iter)) {
        abs_step <- start_step + iter

        updates <- private$.execute_node(current_node, state, config)
        state$update(updates)

        if (!is.null(private$.checkpointer) && !is.null(thread_id)) {
          private$.checkpointer$save(thread_id, abs_step, state$snapshot())
        }

        if (verbose) {
          cli::cli_inform("[{iter}] {current_node} done.")
        }
        if (is.function(on_step)) on_step(current_node, state)

        total_cost <- private$.total_cost()
        if (!is.null(private$.termination) &&
            check_termination(private$.termination, state, iter, total_cost)) {
          if (verbose) cli::cli_inform("Termination condition met at step {iter}.")
          break
        }

        next_node <- private$.resolve_next(current_node, state)
        if (is_sentinel(next_node) && as.character(next_node) == "__END__") break
        current_node <- next_node
      }

      state
    },

    #' @description Stream graph execution, yielding after each node.
    #' @param initial_state Named list of initial channel overrides.
    #' @param config Named list (same keys as `$invoke()`).
    #' @returns A `coro` generator yielding
    #'   `list(node, state_snapshot, iteration)`.
    stream = function(initial_state = list(), config = list()) {
      state       <- private$.init_state(initial_state)
      config      <- private$.enrich_config(config)
      max_iter    <- config$max_iterations %||% 25L
      entry       <- private$.entry_node()
      termination <- private$.termination
      execute_fn  <- private$.execute_node
      resolve_fn  <- private$.resolve_next
      cost_fn     <- private$.total_cost

      gen <- coro::generator(function() {
        current_node <- entry
        for (iter in seq_len(max_iter)) {
          updates <- execute_fn(current_node, state, config)
          state$update(updates)

          coro::yield(list(
            node           = current_node,
            state_snapshot = state$snapshot(),
            iteration      = iter
          ))

          if (!is.null(termination) &&
              check_termination(termination, state, iter, cost_fn())) break

          next_node <- resolve_fn(current_node, state)
          if (is_sentinel(next_node) && as.character(next_node) == "__END__") break
          current_node <- next_node
        }
      })
      gen()
    },

    #' @description Retrieve the last checkpointed state for a thread.
    #' @param thread_id Character.
    #' @returns State snapshot (named list) or `NULL`.
    get_state = function(thread_id) {
      if (is.null(private$.checkpointer)) {
        cli::cli_warn("No checkpointer configured.")
        return(NULL)
      }
      result <- private$.checkpointer$load_latest(thread_id)
      if (is.null(result)) NULL else result$state
    },

    #' @description Manually update a checkpointed state (human-in-the-loop).
    #' @param thread_id Character.
    #' @param updates Named list of channel updates.
    update_state = function(thread_id, updates) {
      if (is.null(private$.checkpointer)) {
        cli::cli_abort("No checkpointer configured.")
      }
      saved <- private$.checkpointer$load_latest(thread_id)
      if (is.null(saved)) {
        cli::cli_abort("No checkpoint found for thread {.val {thread_id}}.")
      }
      snap <- saved$state
      for (k in names(updates)) snap[[k]] <- updates[[k]]
      private$.checkpointer$save(thread_id, saved$step + 1L, snap)
      invisible(NULL)
    },

    #' @description Return a cost report across all agents.
    #' @returns A data frame with columns `agent`, `provider`, `model`,
    #'   `input_tokens`, `output_tokens`, `cost`.
    cost_report = function() {
      build_cost_report(private$.agents)
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

    #' @description Render a visualization of the compiled graph.
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

    #' @description Print runner summary.
    #' @param ... Ignored.
    print = function(...) {
      cli::cli_inform(c(
        "!" = "GraphRunner",
        " " = "Nodes: {length(private$.nodes)}",
        " " = "Agents: {paste(names(private$.agents), collapse = ', ')}",
        " " = "Checkpointer: {class(private$.checkpointer)[[1L]] %||% 'none'}"
      ))
      invisible(self)
    }
  ),

  private = list(
    .nodes             = list(),
    .edges             = list(),
    .conditional_edges = list(),
    .adjacency         = list(),
    .state_schema      = NULL,
    .agents            = list(),
    .checkpointer      = NULL,
    .termination       = NULL,
    .output_channel    = NULL,

    .build_adjacency = function() {
      adj <- list()
      for (e in private$.edges) {
        from_id <- sentinel_id(e$from)
        adj[[from_id]] <- list(type = "fixed", target = e$to)
      }
      for (ce in private$.conditional_edges) {
        from_id <- sentinel_id(ce$from)
        adj[[from_id]] <- list(
          type       = "conditional",
          routing_fn = ce$routing_fn,
          route_map  = ce$route_map
        )
      }
      adj
    },

    .init_state = function(initial_state) {
      state <- WorkflowState$new(private$.state_schema)
      if (!is.null(private$.output_channel)) {
        state$set_output_channel(private$.output_channel)
      }
      if (length(initial_state) > 0L) state$update(initial_state)
      state
    },

    .enrich_config = function(config) {
      config$agents <- private$.agents
      config
    },

    .entry_node = function() {
      entry_info <- private$.adjacency[["__START__"]]
      if (is.null(entry_info)) cli::cli_abort("Graph has no entry edge from START.")
      as.character(entry_info$target)
    },

    .resolve_next = function(current_node, state) {
      info <- private$.adjacency[[current_node]]
      if (is.null(info)) {
        cli::cli_abort("Node {.val {current_node}} has no outgoing edge.")
      }
      if (info$type == "fixed") {
        return(info$target)
      }
      key <- info$routing_fn(state)
      if (!key %in% names(info$route_map)) {
        cli::cli_abort(c(
          "Routing function returned unknown key {.val {key}}.",
          "i" = "Valid keys: {.val {names(info$route_map)}}."
        ))
      }
      info$route_map[[key]]
    },

    .execute_node = function(node_name, state, config) {
      node <- private$.nodes[[node_name]]
      if (is.null(node)) {
        cli::cli_abort("Node {.val {node_name}} is not registered.")
      }
      node_fn <- node$fn
      policy  <- node$retry

      if (is.null(policy)) {
        return(tryCatch(
          node_fn(state, config),
          error = function(e) {
            cli::cli_abort(
              "Error in node {.val {node_name}}: {conditionMessage(e)}",
              parent = e
            )
          }
        ))
      }

      last_error <- NULL
      wait       <- policy$wait_seconds
      for (attempt in seq_len(policy$max_attempts)) {
        result <- tryCatch(
          node_fn(state, config),
          error = function(e) e
        )
        if (!inherits(result, "error")) return(result)
        last_error <- result
        if (attempt < policy$max_attempts) {
          if (wait > 0) Sys.sleep(wait)
          wait <- wait * policy$backoff
        }
      }
      cli::cli_abort(
        c(
          "Node {.val {node_name}} failed after {policy$max_attempts} attempt(s).",
          "x" = "{conditionMessage(last_error)}"
        ),
        parent = last_error
      )
    },

    .total_cost = function() {
      if (length(private$.agents) == 0L) return(0)
      sum(vapply(private$.agents, function(a) a$get_cost(), numeric(1)))
    }
  )
)
