# Build an advisor workflow

A single worker agent produces output; a higher-tier advisor agent
evaluates it and either approves or requests a revision. The worker
revises until approved or `max_revisions` is reached.

## Usage

``` r
advisor_workflow(worker, advisor, max_revisions = 3L, state_schema = NULL)
```

## Arguments

- worker:

  An `Agent` object that produces the draft (typically a lower-cost
  model such as Haiku).

- advisor:

  An `Agent` object that evaluates the draft (typically a
  higher-capability model such as Opus).

- max_revisions:

  Integer. Maximum number of revision cycles (default 3L).

- state_schema:

  A
  [WorkflowState](https://arnold-kakas.github.io/puppeteeR/reference/WorkflowState.md)
  or `NULL` (uses default). The default schema provides: `messages`
  (append), `latest_draft` (overwrite), `advisor_feedback` (overwrite),
  `advisor_verdict` (overwrite), `revision_n` (overwrite).

## Value

A compiled
[GraphRunner](https://arnold-kakas.github.io/puppeteeR/reference/GraphRunner.md).

## Details

Graph:
`START -> worker -> advisor -> (approved -> END | revise -> worker)`.

## Examples

``` r
if (FALSE) { # \dontrun{
runner <- advisor_workflow(
  worker  = agent("writer",  ellmer::chat_anthropic(model = "claude-haiku-4-5-20251001")),
  advisor = agent("advisor", ellmer::chat_anthropic(model = "claude-opus-4-6"))
)
result <- runner$invoke(list(messages = list("Write a concise explanation of R6 classes.")))
result$get("latest_draft")
} # }
```
