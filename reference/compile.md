# Compile a StateGraph into a GraphRunner

Compile a StateGraph into a GraphRunner

## Usage

``` r
compile(
  graph,
  agents = list(),
  checkpointer = NULL,
  termination = NULL,
  output_channel = NULL,
  interrupt_before = character(),
  interrupt_after = character()
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
  or `NULL`. Required when `interrupt_before` or `interrupt_after` is
  non-empty.

- termination:

  A termination condition or `NULL`.

- output_channel:

  Character or `NULL`. Channel returned by `WorkflowState$output()`
  after `$invoke()`.

- interrupt_before:

  Character vector of node names. Execution pauses before each listed
  node and returns control to the caller. Requires a checkpointer and a
  `thread_id` in `config`.

- interrupt_after:

  Character vector of node names. Execution pauses after each listed
  node and returns control to the caller. Requires a checkpointer and a
  `thread_id` in `config`.

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
