# Build a supervisor workflow

Creates a hub-and-spoke graph: a manager agent directs work to worker
agents one at a time. The manager's response is expected to contain the
name of the next worker (or `"DONE"` to stop).

## Usage

``` r
supervisor_workflow(manager, workers, max_rounds = 10L, state_schema = NULL)
```

## Arguments

- manager:

  An `Agent` object acting as the supervisor.

- workers:

  Named list of `Agent` objects.

- max_rounds:

  Integer. Maximum number of manager turns (default 10).

- state_schema:

  A
  [WorkflowState](https://arnold-kakas.github.io/puppeteeR/reference/WorkflowState.md)
  or `NULL` (uses default).

## Value

A compiled
[GraphRunner](https://arnold-kakas.github.io/puppeteeR/reference/GraphRunner.md).

## Examples

``` r
if (FALSE) { # \dontrun{
runner <- supervisor_workflow(
  manager = agent("manager", ellmer::chat_anthropic(),
                  instructions = "Delegate to 'writer' or reply 'DONE'."),
  workers = list(writer = agent("writer", ellmer::chat_anthropic()))
)
result <- runner$invoke(list(messages = list("Write a short story.")))
} # }
```
