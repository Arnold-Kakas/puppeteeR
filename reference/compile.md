# Compile a StateGraph into a GraphRunner

Compile a StateGraph into a GraphRunner

## Usage

``` r
compile(
  graph,
  agents = list(),
  checkpointer = NULL,
  termination = NULL,
  output_channel = NULL
)
```

## Arguments

- graph:

  A
  [StateGraph](https://arnold-kakas.github.io/puppeteeR/reference/StateGraph.md)
  object.

- agents:

  Named list of `Agent` objects.

- checkpointer:

  A
  [Checkpointer](https://arnold-kakas.github.io/puppeteeR/reference/Checkpointer.md)
  or `NULL`.

- termination:

  A termination condition or `NULL`.

- output_channel:

  Character or `NULL`. Channel returned by `WorkflowState$output()`
  after `$invoke()`.

## Value

A
[GraphRunner](https://arnold-kakas.github.io/puppeteeR/reference/GraphRunner.md)
object.

## Examples

``` r
schema <- workflow_state(result = list(default = NULL))
runner <- state_graph(schema) |>
  add_node("step1", function(state, config) list(result = "done")) |>
  add_edge(START, "step1") |>
  add_edge("step1", END) |>
  compile(output_channel = "result")
```
