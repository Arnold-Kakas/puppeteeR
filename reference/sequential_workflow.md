# Build a sequential workflow

Creates a linear chain where each agent receives the last message and
appends its response: `agent1 -> agent2 -> ... -> END`.

## Usage

``` r
sequential_workflow(agents, state_schema = NULL)
```

## Arguments

- agents:

  Named list of `Agent` objects, executed in order.

- state_schema:

  A [WorkflowState](WorkflowState.md) or `NULL` (uses default
  `messages` + [`reducer_append()`](reducer_append.md)).

## Value

A compiled [GraphRunner](GraphRunner.md).

## Examples

``` r
if (FALSE) { # \dontrun{
runner <- sequential_workflow(list(
  writer   = agent("writer",   ellmer::chat_anthropic()),
  reviewer = agent("reviewer", ellmer::chat_anthropic())
))
result <- runner$invoke(list(messages = list("Write a haiku.")))
} # }
```
