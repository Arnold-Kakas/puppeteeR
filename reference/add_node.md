# Add a node to a graph

Add a node to a graph

## Usage

``` r
add_node(graph, name, fn, retry = NULL)
```

## Arguments

- graph:

  A
  [StateGraph](https://arnold-kakas.github.io/puppeteeR/reference/StateGraph.md)
  object.

- name:

  Character. Unique node name.

- fn:

  Function `function(state, config)` returning a named list of state
  updates.

- retry:

  A
  [`retry_policy()`](https://arnold-kakas.github.io/puppeteeR/reference/retry_policy.md)
  object or `NULL`. When non-`NULL`, the runner retries the node on
  error according to the policy.

## Value

`graph`, invisibly (for `|>` chaining).

## Examples

``` r
schema <- workflow_state(result = list(default = NULL))
g <- state_graph(schema) |>
  add_node("step1", function(state, config) list(result = "done"))
```
