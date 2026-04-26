# Event Streaming

puppeteeR provides two ways to observe a running graph:

| Mechanism  | Granularity                                   | How to use                     |
|------------|-----------------------------------------------|--------------------------------|
| `on_step`  | One callback per node, after it finishes      | `config = list(on_step = fn)`  |
| `on_event` | Two callbacks per node - before and after     | `config = list(on_event = fn)` |
| `stream()` | One yielded value per node, after it finishes | `runner$stream()` generator    |

`on_step` and `stream()` exist for simple progress tracking. `on_event`
is the richer replacement: it fires twice per node and carries
structured data, making it suitable for logging, timing, dashboards, and
debugging.

## The event object

Every `on_event` call receives a single list with four fields:

| Field       | Type         | Description                                                          |
|-------------|--------------|----------------------------------------------------------------------|
| `type`      | character    | `"node_start"` or `"node_end"`                                       |
| `node`      | character    | Name of the node being executed                                      |
| `iteration` | integer      | Loop counter (1-based)                                               |
| `data`      | list or NULL | `NULL` on `node_start`; `list(updates = <named list>)` on `node_end` |

`data$updates` on `node_end` is exactly the named list that the node
function returned - the raw state updates before reducers have been
applied.

## Basic usage

``` r
schema <- workflow_state(
  result = list(default = "")
)

runner <- state_graph(schema) |>
  add_node("prepare", function(state, config) list(result = "prepared")) |>
  add_node("finalise", function(state, config) {
    list(result = paste(state$get("result"), "and finalised"))
  }) |>
  add_edge(START, "prepare") |>
  add_edge("prepare", "finalise") |>
  add_edge("finalise", END) |>
  compile()

runner$invoke(config = list(
  on_event = function(event) {
    cat(sprintf("[%s] %s (iter %d)\n", event$type, event$node, event$iteration))
  }
))
#> [node_start] prepare (iter 1)
#> [node_end] prepare (iter 1)
#> [node_start] finalise (iter 2)
#> [node_end] finalise (iter 2)
#> WorkflowState with 1 channel(s):
#> result: chr "prepared and finalised"
```

## Timing nodes

Because `node_start` fires before execution and `node_end` fires after,
you can measure wall-clock time for each node without modifying any node
function:

``` r
timings <- list()
start_times <- list()

runner$invoke(config = list(
  on_event = function(event) {
    if (event$type == "node_start") {
      start_times[[event$node]] <<- proc.time()[["elapsed"]]
    } else {
      elapsed <- proc.time()[["elapsed"]] - start_times[[event$node]]
      timings[[event$node]] <<- elapsed
    }
  }
))
#> WorkflowState with 1 channel(s):
#> result: chr "prepared and finalised"

str(timings)
#> List of 2
#>  $ prepare : num 0.005
#>  $ finalise: num 0.001
```

## Inspecting state updates

`data$updates` on a `node_end` event lets you log exactly what each node
changed without adding [`print()`](https://rdrr.io/r/base/print.html)
calls inside node functions:

``` r
schema2 <- workflow_state(
  count  = list(default = 0L),
  status = list(default = "idle")
)

runner2 <- state_graph(schema2) |>
  add_node("step_a", function(state, config) list(count = 1L, status = "running")) |>
  add_node("step_b", function(state, config) list(count = 2L, status = "done")) |>
  add_edge(START, "step_a") |>
  add_edge("step_a", "step_b") |>
  add_edge("step_b", END) |>
  compile()

runner2$invoke(config = list(
  on_event = function(event) {
    if (event$type == "node_end") {
      cat(sprintf("  %s returned: %s\n",
        event$node,
        paste(names(event$data$updates), collapse = ", ")
      ))
    }
  }
))
#>   step_a returned: count, status
#>   step_b returned: count, status
#> WorkflowState with 2 channel(s):
#> count: int 2
#> status: chr "done"
```

## Building an execution log

Collect events into a data frame for post-run analysis:

``` r
log_entries <- list()

runner2$invoke(config = list(
  on_event = function(event) {
    log_entries[[length(log_entries) + 1L]] <<- data.frame(
      type      = event$type,
      node      = event$node,
      iteration = event$iteration,
      stringsAsFactors = FALSE
    )
  }
))
#> WorkflowState with 2 channel(s):
#> count: int 2
#> status: chr "done"

do.call(rbind, log_entries)
#>         type   node iteration
#> 1 node_start step_a         1
#> 2   node_end step_a         1
#> 3 node_start step_b         2
#> 4   node_end step_b         2
```

## Combining on_event with on_step

`on_step` is kept for backwards compatibility and works alongside
`on_event`. Both can be supplied in the same config - `on_event` fires
first (before and after the node), then `on_step` fires once after the
node completes:

``` r
runner$invoke(config = list(
  on_event = function(event) cat("event:", event$type, event$node, "\n"),
  on_step  = function(node, state) cat("step: ", node, "\n")
))
#> event: node_start prepare 
#> event: node_end prepare 
#> step:  prepare 
#> event: node_start finalise 
#> event: node_end finalise 
#> step:  finalise
#> WorkflowState with 1 channel(s):
#> result: chr "prepared and finalised"
```

## Current limitation - tool-level events

`on_event` currently emits only node-level events. Two additional event
types are planned but not yet available:

| Planned type  | Meaning                               |
|---------------|---------------------------------------|
| `tool_call`   | An LLM inside the node called a tool  |
| `tool_result` | The tool returned a result to the LLM |

These sub-node events require ellmer to expose an intercept hook on
[`ellmer::Chat`](https://ellmer.tidyverse.org/reference/Chat.html) so
puppeteeR can observe individual tool invocations without wrapping the
Chat object. That hook does not exist yet. Once it is added upstream,
`tool_call` and `tool_result` events will be emitted automatically
without any change to the `on_event` API.

Until then, if you need visibility into tool calls, the simplest
workaround is to wrap the tool function itself:

``` r
observed_search <- tool(
  fn = function(query) {
    cat("[tool_call] search:", query, "\n")
    result <- real_search(query)
    cat("[tool_result] search:", nchar(result), "chars\n")
    result
  },
  description = "Search the web",
  arguments = list(query = type_string("Search query"))
)
```

## See also

- [`vignette("checkpointing")`](https://arnold-kakas.github.io/puppeteeR/articles/checkpointing.md) -
  persisting state between runs
- [`vignette("retry-policy")`](https://arnold-kakas.github.io/puppeteeR/articles/retry-policy.md) -
  retrying nodes that fail transiently
- [`?GraphRunner`](https://arnold-kakas.github.io/puppeteeR/reference/GraphRunner.md) -
  full reference for `$invoke()` and `$stream()`
