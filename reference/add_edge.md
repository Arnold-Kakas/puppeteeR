# Add a fixed edge to a graph

Add a fixed edge to a graph

## Usage

``` r
add_edge(graph, from, to)
```

## Arguments

- graph:

  A
  [StateGraph](https://arnold-kakas.github.io/puppeteeR/reference/StateGraph.md)
  object.

- from:

  Node name or
  [START](https://arnold-kakas.github.io/puppeteeR/reference/START.md).

- to:

  Node name or
  [END](https://arnold-kakas.github.io/puppeteeR/reference/END.md).

## Value

`graph`, invisibly.

## Examples

``` r
schema <- workflow_state(result = list(default = NULL))
g <- state_graph(schema) |>
  add_node("step1", function(state, config) list(result = "done")) |>
  add_edge(START, "step1") |>
  add_edge("step1", END)
```
