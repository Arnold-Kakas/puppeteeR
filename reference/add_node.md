# Add a node to a graph

Add a node to a graph

## Usage

``` r
add_node(graph, name, fn)
```

## Arguments

- graph:

  A [StateGraph](StateGraph.md) object.

- name:

  Character. Unique node name.

- fn:

  Function `function(state, config)` returning a named list of state
  updates.

## Value

`graph`, invisibly (for `|>` chaining).

## Examples

``` r
schema <- workflow_state(result = list(default = NULL))
g <- state_graph(schema) |>
  add_node("step1", function(state, config) list(result = "done"))
```
