# Build a debate workflow

Agents take turns in round-robin order responding to each other. An
optional judge agent decides when to stop.

## Usage

``` r
debate_workflow(agents, max_rounds = 5L, judge = NULL, state_schema = NULL)
```

## Arguments

- agents:

  Named list of `Agent` objects participating in the debate.

- max_rounds:

  Integer. Number of full rounds (default 5).

- judge:

  An optional `Agent` that evaluates each round. If `NULL`, the workflow
  stops after `max_rounds * length(agents)` turns.

- state_schema:

  A [WorkflowState](WorkflowState.md) or `NULL` (uses default).

## Value

A compiled [GraphRunner](GraphRunner.md).

## Examples

``` r
if (FALSE) { # \dontrun{
runner <- debate_workflow(
  agents = list(
    pro  = agent("pro",  ellmer::chat_anthropic()),
    con  = agent("con",  ellmer::chat_anthropic())
  ),
  max_rounds = 3L
)
result <- runner$invoke(list(messages = list("Is R better than Python?")))
} # }
```
