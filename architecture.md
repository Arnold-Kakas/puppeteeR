# Architecture

## Overview

puppeteer has six layers, each depending only on the layers below it:

```
┌─────────────────────────────────────────────┐
│  Convenience Workflows (workflows.R)        │  sequential, supervisor, debate
├─────────────────────────────────────────────┤
│  Visualization (viz.R)                      │  DOT, visNetwork, runtime monitor
├─────────────────────────────────────────────┤
│  GraphRunner (runner.R)                     │  Compiled executor, streaming, checkpointing
├─────────────────────────────────────────────┤
│  StateGraph (graph.R)                       │  Builder: nodes, edges, conditional edges
├──────────────────────┬──────────────────────┤
│  Agent (agent.R)     │  WorkflowState       │  LLM wrapper  │  Shared state + reducers
│                      │  (state.R)           │
├──────────────────────┴──────────────────────┤
│  ellmer                                     │  Chat, tool(), parallel_chat(), types
└─────────────────────────────────────────────┘
```

The graph engine (StateGraph, GraphRunner, WorkflowState) is **completely independent of LLM logic**. Node functions are plain R functions. The only connection to LLMs is through Agent objects passed via `config`, which node functions call at their discretion. This means the entire graph engine is testable with mock functions.

---

## Layer 1: Agent (`R/agent.R`)

A thin, opinionated wrapper around `ellmer::Chat`. Adds identity (name, role), conversation management, and cost tracking. Does NOT add LLM logic — all intelligence comes from ellmer.

### R6 Class: Agent

```r
Agent <- R6Class("Agent",
  public = list(
    initialize = function(name, chat, role = NULL, instructions = NULL,
                          tools = list(), handoffs = character()) {
      # Validates inputs, prepends role/instructions to system prompt,
      # registers tools on the chat object
    },

    chat = function(...) {
      # Delegates to private$.chat$chat(...)
      # After: accumulates cost via private$.track_cost()
      # Returns: character string (the assistant's response)
    },

    chat_structured = function(..., type) {
      # Delegates to private$.chat$chat_structured(..., type = type)
      # Returns: parsed R object matching the type spec
    },

    stream = function(...) {
      # Delegates to private$.chat$stream(...)
      # Returns: coro generator yielding text chunks
    },

    clone_fresh = function() {
      # Returns a new Agent with same config but empty conversation history
      # Uses: chat$clone(deep = TRUE) then chat$set_turns(list())
    },

    get_turns = function() {
      private$.chat$get_turns()
    },

    set_turns = function(turns) {
      private$.chat$set_turns(turns)
    },

    get_cost = function() {
      private$.cumulative_cost
    },

    get_tokens = function() {
      private$.cumulative_tokens
    },

    print = function(...) {
      # cli-formatted summary: name, role, provider, model, tools, cost
    }
  ),

  active = list(
    name = function() private$.name,
    role = function() private$.role,
    provider = function() private$.chat$get_provider(),
    model = function() private$.chat$get_model(),
    tool_names = function() {
      vapply(private$.chat$get_tools(), function(t) t@name, character(1))
    }
  ),

  private = list(
    .name = NULL,
    .chat = NULL,
    .role = NULL,
    .instructions = NULL,
    .cumulative_cost = 0,
    .cumulative_tokens = list(input = 0L, output = 0L),

    .track_cost = function() {
      cost <- private$.chat$get_cost(include = "last")
      tokens <- private$.chat$get_tokens()
      private$.cumulative_cost <- private$.cumulative_cost + sum(cost$cost, na.rm = TRUE)
      last_tokens <- tokens[nrow(tokens), ]
      private$.cumulative_tokens$input <- private$.cumulative_tokens$input + last_tokens$input
      private$.cumulative_tokens$output <- private$.cumulative_tokens$output + last_tokens$output
    }
  )
)
```

### Constructor function (exported)

```r
agent <- function(name, chat, role = NULL, instructions = NULL,
                  tools = list(), handoffs = character()) {
  Agent$new(name = name, chat = chat, role = role,
            instructions = instructions, tools = tools, handoffs = handoffs)
}
```

---

## Layer 2: WorkflowState (`R/state.R`)

Mutable shared state passed between nodes. Each named channel has a default value and a reducer function that controls how updates merge.

### R6 Class: WorkflowState

```r
WorkflowState <- R6Class("WorkflowState",
  public = list(
    initialize = function(schema) {
      # schema is a named list: list(channel_name = list(default = ..., reducer = ...))
      # Validates all channels have default and reducer
      # Initializes private$.data from defaults
      # Stores reducers in private$.reducers
    },

    get = function(key) {
      # Returns current value of channel `key`
      # cli_abort if key not in schema
    },

    set = function(key, value) {
      # Applies reducer: private$.data[[key]] <- private$.reducers[[key]](old, value)
    },

    update = function(updates) {
      # updates is a named list
      # Calls self$set() for each key-value pair
      # Ignores keys starting with "." (reserved for internal metadata)
      # cli_abort if any key not in schema (typo protection)
    },

    snapshot = function() {
      # Returns a deep copy of private$.data as a plain list
      # Used by checkpointer
    },

    restore = function(snapshot) {
      # Replaces private$.data with snapshot
      # Validates keys match schema
    },

    keys = function() {
      names(private$.data)
    },

    print = function(...) {
      # cli-formatted: channel names, types, current values (truncated)
    }
  ),

  private = list(
    .data = list(),
    .reducers = list(),
    .schema = list()
  )
)
```

### Constructor + reducers (exported)

```r
workflow_state <- function(...) {
  schema <- list(...)
  # Validate each element is list(default = ..., reducer = ...)
  # If reducer missing, default to reducer_overwrite()
  WorkflowState$new(schema)
}

reducer_overwrite <- function() {
  function(old, new) new
}

reducer_append <- function() {
  function(old, new) c(old, list(new))
}

reducer_merge <- function() {
  function(old, new) modifyList(old, new)
}
```

---

## Layer 3: StateGraph (`R/graph.R`)

A builder for directed graphs. Nodes are named functions. Edges connect nodes (fixed or conditional). The graph is validated and compiled into a GraphRunner.

### R6 Class: StateGraph

```r
StateGraph <- R6Class("StateGraph",
  public = list(
    initialize = function(state_schema) {
      # state_schema: either a WorkflowState object or a named list (converted to one)
      # Initializes empty node and edge registries
    },

    add_node = function(name, fn) {
      # fn signature: function(state, config) -> named list of updates
      # Validates name is unique, fn is a function
      # Stores in private$.nodes[[name]] = list(fn = fn)
      # Returns self (chainable)
    },

    add_edge = function(from, to) {
      # Fixed edge: always traverse from -> to
      # from/to can be node names, START, or END sentinels
      # Validates nodes exist (or are START/END)
      # cli_abort if `from` already has a fixed edge (no fan-out on fixed edges)
      # Stores in private$.edges
      # Returns self
    },

    add_conditional_edge = function(from, routing_fn, route_map) {
      # routing_fn: function(state) -> character(1) key
      # route_map: named list mapping keys to node names or END
      # Validates `from` exists, all route_map targets exist
      # Stores in private$.conditional_edges
      # Returns self
    },

    set_entry = function(name) {
      # Shortcut for add_edge(START, name)
      # Returns self
    },

    compile = function(agents = list(), checkpointer = NULL,
                       termination = NULL) {
      # Validates the graph:
      #   - Exactly one edge from START
      #   - All nodes reachable from START
      #   - At least one path reaches END
      #   - No node has both a fixed edge and conditional edge leaving it
      # Returns GraphRunner$new(nodes, edges, conditional_edges,
      #   state_schema, agents, checkpointer, termination)
    },

    # --- Visualization methods (delegate to viz.R) ---

    visualize = function(engine = c("dot", "visnetwork", "mermaid")) {
      # Generates and renders the graph visualization
      # "dot" -> grViz in viewer
      # "visnetwork" -> interactive visNetwork
      # "mermaid" -> mermaid string (for Quarto)
    },

    as_dot = function() {
      # Returns DOT language string for the graph
    },

    as_mermaid = function() {
      # Returns mermaid diagram string
    },

    export_diagram = function(path, width = 800, height = 600) {
      # Exports to SVG/PNG based on file extension
    },

    print = function(...) {
      # Prints: node count, edge count, entry point, endpoints
      # Optionally prints ASCII art of the graph
    }
  ),

  private = list(
    .nodes = list(),
    .edges = list(),          # list of list(from, to)
    .conditional_edges = list(), # list of list(from, routing_fn, route_map)
    .state_schema = NULL
  )
)
```

### Sentinels (exported constants)

```r
START <- structure("__START__", class = "puppeteer_sentinel")
END   <- structure("__END__", class = "puppeteer_sentinel")
```

### Constructor (exported)

```r
state_graph <- function(state_schema) {
  if (!inherits(state_schema, "WorkflowState")) {
    state_schema <- do.call(workflow_state, state_schema)
  }
  StateGraph$new(state_schema)
}
```

### Pipe support

All builder methods return `self`, so the pipe works:

```r
graph <- state_graph(schema) |>
  add_node("a", fn_a) |>
  add_node("b", fn_b) |>
  add_edge(START, "a") |>
  add_edge("a", "b") |>
  add_edge("b", END)
```

Wait — R6 methods aren't generic functions, so `|>` won't work this way with method calls. Two options:

**Option A**: Export standalone generics that dispatch on the graph object:

```r
add_node <- function(graph, name, fn) {
  graph$add_node(name, fn)
}

add_edge <- function(graph, from, to) {
  graph$add_edge(from, to)
}

add_conditional_edge <- function(graph, from, routing_fn, route_map) {
  graph$add_conditional_edge(from, routing_fn, route_map)
}
```

These return the graph (since the R6 methods return `self`), making the pipe chain work.

**Option B**: S3 generics. Overkill for this.

**Decision: Option A.** Export thin wrapper functions. This is the pattern `targets` and other R6-heavy packages use.

---

## Layer 4: GraphRunner (`R/runner.R`)

The compiled, executable graph. Handles topological execution, conditional routing, cycle detection, checkpointing, termination, and cost aggregation.

### R6 Class: GraphRunner

```r
GraphRunner <- R6Class("GraphRunner",
  public = list(
    initialize = function(nodes, edges, conditional_edges,
                          state_schema, agents, checkpointer, termination) {
      # Stores all graph structure
      # Pre-computes adjacency list for traversal
      # Validates agents list (named list of Agent objects)
    },

    invoke = function(initial_state = list(), config = list()) {
      # config keys:
      #   thread_id    — character, identifies this execution (for checkpointing)
      #   max_iterations — integer, cycle guard (default 25)
      #   on_step      — function(node_name, state) callback, called after each node
      #
      # Algorithm:
      # 1. Initialize WorkflowState from schema + initial_state overrides
      # 2. If checkpointer + thread_id, try to restore from checkpoint
      # 3. current_node <- entry node (from START edge)
      # 4. Loop:
      #    a. Execute node function: updates <- node$fn(state, config_with_agents)
      #    b. Apply updates to state via state$update(updates)
      #    c. Track cost from all agents
      #    d. Checkpoint if checkpointer present
      #    e. Check termination conditions
      #    f. Determine next node:
      #       - If fixed edge exists -> follow it
      #       - If conditional edge -> call routing_fn(state), look up route_map
      #       - If next is END -> break
      #    g. Increment iteration counter, check max_iterations
      # 5. Return state (WorkflowState object)
    },

    stream = function(initial_state = list(), config = list()) {
      # Returns a coro::generator that yields after each node execution:
      # list(node = "name", state = snapshot, duration = seconds, iteration = n)
      # Caller consumes with for loop or coro::collect()
    },

    invoke_async = function(initial_state = list(), config = list()) {
      # Returns a promises::promise that resolves to final state
      # Uses ellmer's $chat_async() internally
      # For Shiny integration
    },

    get_state = function(thread_id) {
      # Retrieves last checkpointed state for a thread
      # Returns NULL if no checkpoint exists
    },

    update_state = function(thread_id, updates) {
      # Manually updates checkpointed state (human-in-the-loop)
      # Then resume with invoke(config = list(thread_id = thread_id))
    },

    cost_report = function() {
      # Returns tibble aggregating cost across all agents:
      # agent | provider | model | input_tokens | output_tokens | cost
      # Sources data from each Agent$get_cost() and Agent$get_tokens()
    },

    print = function(...) {
      # Summary: node count, edge count, agents, checkpointer type
    }
  ),

  private = list(
    .nodes = list(),
    .edges = list(),
    .conditional_edges = list(),
    .adjacency = list(),       # pre-computed: node_name -> list(type, target(s))
    .state_schema = NULL,
    .agents = list(),
    .checkpointer = NULL,
    .termination = NULL,

    .resolve_next = function(current_node, state) {
      # Checks fixed edges first, then conditional edges
      # Returns node name or END sentinel
      # cli_abort if conditional routing returns unknown key
    },

    .execute_node = function(node_name, state, config) {
      # Calls node function with state and enriched config (agents injected)
      # Wraps in tryCatch for user-friendly errors
      # Returns named list of state updates
    }
  )
)
```

### Execution model (detailed)

```
START
  │
  ▼
┌──────────┐     execute fn     ┌──────────┐
│  Node A  │ ──────────────►    │  State   │  (updates applied via reducers)
└──────────┘                    └──────────┘
  │                                 │
  │  resolve next edge              │
  ▼                                 │
  conditional_edge(routing_fn) ◄────┘
  │
  ├── key "x" ──► Node B
  ├── key "y" ──► Node C
  └── key "z" ──► END

Each iteration:
1. fn(state, config) -> updates
2. state$update(updates)
3. checkpoint(state)
4. check termination
5. resolve next node
6. if END or max_iterations -> stop
```

---

## Layer 5: Checkpointer (`R/checkpointer.R`)

Abstract interface + concrete implementations. Saves state snapshots keyed by `(thread_id, step_number)`.

### Base class + implementations

```r
Checkpointer <- R6Class("Checkpointer",
  public = list(
    save = function(thread_id, step, state_snapshot) {
      cli_abort("Subclass must implement $save()")
    },

    load_latest = function(thread_id) {
      # Returns list(step = n, state = snapshot) or NULL
      cli_abort("Subclass must implement $load_latest()")
    },

    load_step = function(thread_id, step) {
      # Returns state snapshot at exact step, or NULL
      cli_abort("Subclass must implement $load_step()")
    },

    list_threads = function() {
      cli_abort("Subclass must implement $list_threads()")
    }
  )
)

MemoryCheckpointer <- R6Class("MemoryCheckpointer",
  inherit = Checkpointer,
  public = list(
    initialize = function() {
      private$.store <- list()
    },
    save = function(thread_id, step, state_snapshot) {
      if (is.null(private$.store[[thread_id]])) {
        private$.store[[thread_id]] <- list()
      }
      private$.store[[thread_id]][[as.character(step)]] <- state_snapshot
    },
    load_latest = function(thread_id) {
      thread <- private$.store[[thread_id]]
      if (is.null(thread) || length(thread) == 0) return(NULL)
      steps <- as.integer(names(thread))
      max_step <- max(steps)
      list(step = max_step, state = thread[[as.character(max_step)]])
    },
    load_step = function(thread_id, step) {
      private$.store[[thread_id]][[as.character(step)]]
    },
    list_threads = function() {
      names(private$.store)
    }
  ),
  private = list(.store = NULL)
)

RDSCheckpointer <- R6Class("RDSCheckpointer",
  inherit = Checkpointer,
  # Saves each checkpoint as: {dir}/{thread_id}/step_{n}.rds
  # load_latest scans directory for highest step number
)

SQLiteCheckpointer <- R6Class("SQLiteCheckpointer",
  inherit = Checkpointer,
  # Table: checkpoints(thread_id TEXT, step INTEGER, state BLOB, created_at TEXT)
  # Uses DBI + RSQLite
  # state serialized with serialize(..., connection = NULL) -> raw
)
```

### Constructor functions (exported)

```r
memory_checkpointer <- function() MemoryCheckpointer$new()
rds_checkpointer <- function(dir) RDSCheckpointer$new(dir)
sqlite_checkpointer <- function(path) SQLiteCheckpointer$new(path)
```

---

## Layer 5b: TerminationCondition (`R/termination.R`)

Composable stop conditions. S3 classes with `|` and `&` operators.

```r
# --- Constructors ---

max_turns <- function(n) {
  structure(list(n = n), class = c("max_turns", "termination_condition"))
}

cost_limit <- function(dollars) {
  structure(list(dollars = dollars), class = c("cost_limit", "termination_condition"))
}

text_match <- function(pattern, channel = "messages") {
  structure(list(pattern = pattern, channel = channel),
            class = c("text_match", "termination_condition"))
}

custom_condition <- function(fn) {
  structure(list(fn = fn), class = c("custom_condition", "termination_condition"))
}

# --- Check method (internal) ---

check_termination <- function(condition, state, iteration, total_cost) {
  UseMethod("check_termination")
}

check_termination.max_turns <- function(condition, state, iteration, total_cost) {
  iteration >= condition$n
}

check_termination.cost_limit <- function(condition, state, iteration, total_cost) {
  total_cost >= condition$dollars
}

check_termination.text_match <- function(condition, state, iteration, total_cost) {
  value <- state$get(condition$channel)
  if (is.list(value)) value <- paste(unlist(value), collapse = " ")
  grepl(condition$pattern, value, fixed = TRUE)
}

check_termination.custom_condition <- function(condition, state, iteration, total_cost) {
  condition$fn(state)
}

# --- Composition operators ---

"|.termination_condition" <- function(a, b) {
  structure(list(a = a, b = b), class = c("or_condition", "termination_condition"))
}

"&.termination_condition" <- function(a, b) {
  structure(list(a = a, b = b), class = c("and_condition", "termination_condition"))
}

check_termination.or_condition <- function(condition, state, iteration, total_cost) {
  check_termination(condition$a, state, iteration, total_cost) ||
    check_termination(condition$b, state, iteration, total_cost)
}

check_termination.and_condition <- function(condition, state, iteration, total_cost) {
  check_termination(condition$a, state, iteration, total_cost) &&
    check_termination(condition$b, state, iteration, total_cost)
}
```

Usage: `max_turns(20) | cost_limit(5.00)`

---

## Layer 6: Visualization (`R/viz.R`)

Two distinct concerns: **static graph structure** (design-time) and **runtime monitoring** (execution-time).

### Static visualization: graph structure

Generate visual representations of the StateGraph before execution.

```r
# --- DOT generation (core, no optional deps) ---

as_dot.StateGraph <- function(graph) {
  # Generates Graphviz DOT string from graph structure
  # Node shapes:
  #   START/END -> oval, filled dark
  #   Regular nodes -> rectangle, rounded corners
  #   Nodes with conditional outgoing edges -> diamond-shaped label annotation
  # Edge styles:
  #   Fixed edges -> solid arrows
  #   Conditional edges -> dashed arrows, labeled with route key
  # Returns: character(1) DOT string

  nodes <- private$.nodes
  edges <- private$.edges
  cond_edges <- private$.conditional_edges

  dot_lines <- c(
    "digraph workflow {",
    "  graph [rankdir=TB, fontname=\"Helvetica\", bgcolor=\"transparent\"]",
    "  node [shape=rect, style=\"rounded,filled\", fontname=\"Helvetica\", fillcolor=\"#E8F0FE\", color=\"#4A90D9\"]",
    "  edge [fontname=\"Helvetica\", fontsize=10, color=\"#666666\"]",
    "",
    "  __START__ [label=\"START\", shape=oval, fillcolor=\"#2D3748\", fontcolor=white]",
    "  __END__ [label=\"END\", shape=oval, fillcolor=\"#2D3748\", fontcolor=white]"
  )

  # Add node definitions
  for (name in names(nodes)) {
    has_conditional <- any(vapply(cond_edges, function(e) e$from == name, logical(1)))
    if (has_conditional) {
      dot_lines <- c(dot_lines, sprintf("  %s [label=\"%s\", fillcolor=\"#FFF3CD\"]", name, name))
    } else {
      dot_lines <- c(dot_lines, sprintf("  %s [label=\"%s\"]", name, name))
    }
  }

  # Add fixed edges
  for (edge in edges) {
    from <- if (inherits(edge$from, "puppeteer_sentinel")) "__START__" else edge$from
    to <- if (inherits(edge$to, "puppeteer_sentinel")) "__END__" else edge$to
    dot_lines <- c(dot_lines, sprintf("  %s -> %s", from, to))
  }

  # Add conditional edges
  for (ce in cond_edges) {
    from <- ce$from
    for (key in names(ce$route_map)) {
      to <- ce$route_map[[key]]
      if (inherits(to, "puppeteer_sentinel")) to <- "__END__"
      dot_lines <- c(dot_lines,
        sprintf("  %s -> %s [label=\"%s\", style=dashed]", from, to, key))
    }
  }

  dot_lines <- c(dot_lines, "}")
  paste(dot_lines, collapse = "\n")
}

# --- Mermaid generation ---

as_mermaid.StateGraph <- function(graph) {
  # Similar logic, outputs mermaid syntax:
  # graph TD
  #   START((START)) --> classify[classify]
  #   classify -- "urgent" --> draft[draft_reply]
  #   classify -- "spam" --> END((END))
}

# --- Rendering ---

visualize_graph <- function(graph, engine = c("dot", "visnetwork", "mermaid")) {
  engine <- rlang::arg_match(engine)

  switch(engine,
    dot = {
      rlang::check_installed("DiagrammeR", reason = "to render DOT diagrams")
      DiagrammeR::grViz(as_dot(graph))
    },
    visnetwork = {
      rlang::check_installed("visNetwork", reason = "for interactive visualization")
      build_visnetwork(graph)
    },
    mermaid = {
      cat(as_mermaid(graph))
    }
  )
}

# --- visNetwork builder (internal) ---

build_visnetwork <- function(graph) {
  # Builds nodes data.frame: id, label, shape, color, title (tooltip)
  # Builds edges data.frame: from, to, label, dashes, arrows
  # Applies hierarchical layout (direction = "UD")
  # Enables highlight nearest, node selection
  # Returns visNetwork htmlwidget

  nodes_df <- data.frame(
    id = c("__START__", names(graph$.__enclos_env__$private$.nodes), "__END__"),
    label = c("START", names(graph$.__enclos_env__$private$.nodes), "END"),
    shape = c("circle", rep("box", length(graph$.__enclos_env__$private$.nodes)), "circle"),
    color = c("#2D3748", rep("#E8F0FE", length(graph$.__enclos_env__$private$.nodes)), "#2D3748"),
    font.color = c("white", rep("black", length(graph$.__enclos_env__$private$.nodes)), "white"),
    stringsAsFactors = FALSE
  )

  # ... build edges_df similarly ...

  visNetwork::visNetwork(nodes_df, edges_df) |>
    visNetwork::visHierarchicalLayout(direction = "UD") |>
    visNetwork::visOptions(highlightNearest = TRUE) |>
    visNetwork::visEdges(arrows = "to")
}

# --- Export ---

export_diagram <- function(graph, path, width = 800, height = 600) {
  rlang::check_installed("DiagrammeR", reason = "to export diagrams")
  rlang::check_installed("DiagrammeRsvg", reason = "to export diagrams")

  svg_str <- DiagrammeRsvg::export_svg(DiagrammeR::grViz(as_dot(graph)))

  ext <- tolower(tools::file_ext(path))
  if (ext == "svg") {
    writeLines(svg_str, path)
  } else if (ext == "png") {
    rlang::check_installed("rsvg", reason = "to export PNG diagrams")
    rsvg::rsvg_png(charToRaw(svg_str), file = path, width = width, height = height)
  } else {
    cli::cli_abort("Unsupported format: {.val {ext}}. Use .svg or .png.")
  }

  invisible(path)
}
```

### Runtime visualization: execution monitoring

Track and display what's happening during workflow execution.

```r
# --- Step logger (internal, used by GraphRunner) ---

StepLog <- R6Class("StepLog",
  public = list(
    initialize = function() {
      private$.entries <- list()
    },

    record = function(node, iteration, duration, cost_delta, state_keys_changed) {
      entry <- list(
        node = node,
        iteration = iteration,
        timestamp = Sys.time(),
        duration_secs = duration,
        cost_delta = cost_delta,
        state_keys_changed = state_keys_changed
      )
      private$.entries <- c(private$.entries, list(entry))
    },

    as_tibble = function() {
      # Returns tibble: node, iteration, timestamp, duration_secs, cost_delta, state_keys_changed
    },

    print_step = function(entry) {
      # cli-formatted live output:
      # ● [2/5] classify (0.8s, $0.001) → updated: classification
      cli::cli_inform(
        "{.strong [{entry$iteration}]} {.field {entry$node}} ({round(entry$duration_secs, 1)}s, ${format(entry$cost_delta, digits=3)}) \
         {cli::symbol$arrow_right} {paste(entry$state_keys_changed, collapse = ', ')}"
      )
    }
  ),

  private = list(.entries = NULL)
)

# --- Cost report (used by GraphRunner$cost_report()) ---

build_cost_report <- function(agents) {
  # Iterates over all Agent objects
  # Collects: agent$name, agent$provider, agent$model, agent$get_tokens(), agent$get_cost()
  # Returns tibble with columns: agent, provider, model, input_tokens, output_tokens, cost
  # Adds a totals row at the bottom

  rows <- lapply(agents, function(a) {
    tokens <- a$get_tokens()
    data.frame(
      agent = a$name,
      provider = a$provider,
      model = a$model,
      input_tokens = tokens$input,
      output_tokens = tokens$output,
      cost = a$get_cost(),
      stringsAsFactors = FALSE
    )
  })

  do.call(rbind, rows)
}

# --- Shiny module (exported, optional) ---

# For users who want a live dashboard in Shiny:

puppeteer_monitor_ui <- function(id) {
  ns <- shiny::NS(id)
  rlang::check_installed("shiny")
  shiny::tagList(
    visNetwork::visNetworkOutput(ns("graph"), height = "400px"),
    shiny::tableOutput(ns("steps")),
    shiny::verbatimTextOutput(ns("cost"))
  )
}

puppeteer_monitor_server <- function(id, runner, initial_state, config) {
  # Reactive: runs the workflow via runner$stream()
  # Updates visNetwork to highlight the active node
  # Updates step table as each node completes
  # Updates cost summary
}
```

### Visualization summary

| Function | Input | Output | Optional deps |
|---|---|---|---|
| `as_dot()` | StateGraph | DOT string | none |
| `as_mermaid()` | StateGraph | Mermaid string | none |
| `visualize()` | StateGraph | Rendered widget | DiagrammeR or visNetwork |
| `export_diagram()` | StateGraph + path | SVG/PNG file | DiagrammeR, DiagrammeRsvg, rsvg |
| `cost_report()` | GraphRunner | tibble | none |
| `puppeteer_monitor_ui/server()` | Shiny module | Live dashboard | shiny, visNetwork |

---

## Layer 7: Convenience Workflows (`R/workflows.R`)

Pre-built graph patterns that compile to GraphRunners.

```r
sequential_workflow <- function(agents, state_schema = NULL) {
  # Creates a linear chain: agent1 -> agent2 -> ... -> END
  # Each node calls the corresponding agent with the accumulated messages
  # Default state: messages channel with reducer_append()
  #
  # Implementation:
  # 1. Build default state_schema if not provided
  # 2. Create StateGraph
  # 3. For each agent, add_node with a function that:
  #    a. Gets messages from state
  #    b. Calls agent$chat(last_message)
  #    c. Returns list(messages = response)
  # 4. Wire edges: START -> agent1 -> agent2 -> ... -> END
  # 5. Compile with agents list
}

supervisor_workflow <- function(manager, workers, max_rounds = 10,
                                state_schema = NULL) {
  # Creates a hub-and-spoke: manager -> conditional -> workers -> manager (loop)
  #
  # Graph structure:
  #   START -> manager
  #   manager -> conditional_edge(routing_fn, workers + DONE->END)
  #   each worker -> manager
  #
  # The manager's response is parsed to extract the worker name
  # routing_fn checks if response matches a worker name or "DONE"
  # max_rounds enforced via max_turns() termination condition
  #
  # Implementation:
  # 1. Create state with messages + current_task + round channels
  # 2. Manager node: chat with accumulated context, return response
  # 3. Routing fn: parse manager response, match to worker names
  # 4. Worker nodes: each calls their agent, appends result to messages
  # 5. Compile with termination = max_turns(max_rounds)
}

debate_workflow <- function(agents, max_rounds = 5, judge = NULL,
                            state_schema = NULL) {
  # Round-robin: agents take turns responding to each other
  # Optional judge agent decides when to stop
  #
  # Graph structure (with judge):
  #   START -> agent1 -> agent2 -> ... -> agentN -> judge
  #   judge -> conditional_edge: "continue" -> agent1, "done" -> END
  #
  # Graph structure (without judge):
  #   START -> agent1 -> agent2 -> ... -> agentN -> agent1 (cycle)
  #   Termination: max_turns(max_rounds * length(agents))
}
```

---

## Exported API surface summary

### Core constructors

| Function | Returns | File |
|---|---|---|
| `agent()` | Agent | agent.R |
| `workflow_state()` | WorkflowState | state.R |
| `state_graph()` | StateGraph | graph.R |

### Graph builder functions (pipe-friendly wrappers)

| Function | Returns | File |
|---|---|---|
| `add_node(graph, name, fn)` | StateGraph (self) | graph.R |
| `add_edge(graph, from, to)` | StateGraph (self) | graph.R |
| `add_conditional_edge(graph, from, routing_fn, route_map)` | StateGraph (self) | graph.R |

### State utilities

| Function | Returns | File |
|---|---|---|
| `reducer_overwrite()` | function | state.R |
| `reducer_append()` | function | state.R |
| `reducer_merge()` | function | state.R |

### Checkpointers

| Function | Returns | File |
|---|---|---|
| `memory_checkpointer()` | MemoryCheckpointer | checkpointer.R |
| `rds_checkpointer(dir)` | RDSCheckpointer | checkpointer.R |
| `sqlite_checkpointer(path)` | SQLiteCheckpointer | checkpointer.R |

### Termination conditions

| Function | Returns | File |
|---|---|---|
| `max_turns(n)` | termination_condition | termination.R |
| `cost_limit(dollars)` | termination_condition | termination.R |
| `text_match(pattern, channel)` | termination_condition | termination.R |
| `custom_condition(fn)` | termination_condition | termination.R |

### Convenience workflows

| Function | Returns | File |
|---|---|---|
| `sequential_workflow(agents)` | GraphRunner | workflows.R |
| `supervisor_workflow(manager, workers)` | GraphRunner | workflows.R |
| `debate_workflow(agents)` | GraphRunner | workflows.R |

### Visualization

| Function | Returns | File |
|---|---|---|
| `visualize(graph, engine)` | widget or string | viz.R |
| `as_dot(graph)` | character | viz.R |
| `as_mermaid(graph)` | character | viz.R |
| `export_diagram(graph, path)` | invisible(path) | viz.R |
| `puppeteer_monitor_ui(id)` | Shiny UI | viz.R |
| `puppeteer_monitor_server(id, ...)` | Shiny server | viz.R |

### Constants

| Name | Value | File |
|---|---|---|
| `START` | sentinel | graph.R |
| `END` | sentinel | graph.R |

### Total exported: ~25 functions/objects

This is the complete public API. Everything else is internal (private R6 methods, helper functions, S3 dispatch methods for termination).
