# Add a conditional edge to a graph

Add a conditional edge to a graph

## Usage

``` r
add_conditional_edge(graph, from, routing_fn, route_map)
```

## Arguments

- graph:

  A [StateGraph](StateGraph.md) object.

- from:

  Character. Source node name.

- routing_fn:

  Function `function(state)` returning a key in `route_map`.

- route_map:

  Named list mapping routing keys to target node names or [END](END.md).

## Value

`graph`, invisibly.

## Examples

``` r
schema <- workflow_state(
  value = list(default = 0L),
  result = list(default = NULL)
)
g <- state_graph(schema) |>
  add_node("check", function(state, config) list()) |>
  add_node("high",  function(state, config) list(result = "high")) |>
  add_node("low",   function(state, config) list(result = "low")) |>
  add_edge(START, "check") |>
  add_conditional_edge(
    "check",
    routing_fn  = function(state) if (state$get("value") > 5L) "hi" else "lo",
    route_map   = list(hi = "high", lo = "low")
  ) |>
  add_edge("high", END) |>
  add_edge("low",  END)
```
