# Build a planner workflow

A high-tier planner agent creates a step-by-step plan; a pure-R
dispatcher routes each step to the appropriate worker agent (no LLM call
per dispatch); an optional evaluator agent decides whether the results
are complete or require replanning.

## Usage

``` r
planner_workflow(
  planner,
  workers,
  evaluator = NULL,
  max_replans = 2L,
  max_steps = 10L,
  parse_plan = NULL,
  state_schema = NULL
)
```

## Arguments

- planner:

  An `Agent` object used for planning (typically a high-capability model
  such as Opus).

- workers:

  Named list of `Agent` objects that execute plan steps.

- evaluator:

  An optional `Agent` object that reviews completed results. If `NULL`,
  the workflow ends when the plan is exhausted.

- max_replans:

  Integer. Maximum number of replanning rounds (default 2L).

- max_steps:

  Integer. Expected maximum plan length, used to size the termination
  guard (default 10L).

- parse_plan:

  Optional `function(text)` that converts the planner's raw response
  into a list of `list(worker, instruction)` items. If `NULL`, a default
  line-by-line parser expecting `worker_name: instruction` is used.

- state_schema:

  A
  [WorkflowState](https://arnold-kakas.github.io/puppeteeR/reference/WorkflowState.md)
  or `NULL` (uses default).

## Value

A compiled
[GraphRunner](https://arnold-kakas.github.io/puppeteeR/reference/GraphRunner.md).

## Details

Graph:
`START -> planner -> dispatcher -> [workers] -> dispatcher -> ... -> evaluator -> (done -> END | replan -> planner)`.

The planner must respond with one step per line in the format
`worker_name: instruction`. A custom `parse_plan` function can be
supplied to handle alternative formats.

## Examples

``` r
if (FALSE) { # \dontrun{
runner <- planner_workflow(
  planner   = agent("planner",    ellmer::chat_anthropic(model = "claude-opus-4-6"),
                    instructions = "Break tasks into steps for 'researcher' and 'writer'."),
  workers   = list(
    researcher = agent("researcher", ellmer::chat_anthropic(model = "claude-haiku-4-5-20251001")),
    writer     = agent("writer",     ellmer::chat_anthropic(model = "claude-haiku-4-5-20251001"))
  ),
  evaluator = agent("evaluator",  ellmer::chat_anthropic(model = "claude-opus-4-6"))
)
result <- runner$invoke(list(messages = list("Write a short report on tidy data.")))
result$get("results")
} # }
```
