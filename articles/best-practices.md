# Best Practices

A collection of practical guidance for building reliable, cost-efficient
multi-agent workflows.

## Model selection

Anthropic’s model tiers differ significantly in capability and cost.
Matching the tier to the task is the single highest-leverage cost
optimisation available.

| Model             | ID                          | Best for                                                   |
|-------------------|-----------------------------|------------------------------------------------------------|
| Claude Haiku 4.5  | `claude-haiku-4-5-20251001` | Simple execution tasks, text transformation, summarisation |
| Claude Sonnet 4.6 | `claude-sonnet-4-6`         | Balanced general work, most supervisor workers             |
| Claude Opus 4.6   | `claude-opus-4-6`           | Planning, evaluation, complex reasoning, final judgement   |

``` r
library(ellmer)

# Cheap workers for execution
researcher <- agent("researcher",
  chat_anthropic(model = "claude-haiku-4-5-20251001"),
  instructions = "Research thoroughly and return structured notes."
)

# Balanced model for most tasks
analyst <- agent("analyst",
  chat_anthropic(model = "claude-sonnet-4-6"),
  instructions = "Analyse the notes and identify key patterns."
)

# Expensive model only where judgement matters
reviewer <- agent("reviewer",
  chat_anthropic(model = "claude-opus-4-6"),
  instructions = "Review the analysis and approve or request revisions."
)
```

**General rules:**

- Use Haiku for any node that does mechanical work: formatting,
  extraction, lookup, first-pass drafts.
- Use Sonnet for nodes that require coherent reasoning but not top-tier
  capability.
- Reserve Opus for the planner, evaluator, or advisor — nodes that are
  called once per round rather than once per step.

The
[`advisor_workflow()`](https://arnold-kakas.github.io/puppeteeR/reference/advisor_workflow.md)
and
[`planner_workflow()`](https://arnold-kakas.github.io/puppeteeR/reference/planner_workflow.md)
constructors are designed around this split: see
[`vignette("workflows")`](https://arnold-kakas.github.io/puppeteeR/articles/workflows.md).

## Context management

### The unbounded context problem

Several workflows pass the full message history to every LLM call. By
default the `messages` channel uses
[`reducer_append()`](https://arnold-kakas.github.io/puppeteeR/reference/reducer_append.md),
which grows indefinitely. In a 6-round debate with two agents, the last
node receives a prompt containing all 12 prior messages — which can
exceed tens of thousands of tokens and cause the API to close the
connection mid-stream:

    Warning: ! Agent "pessimist": API error on attempt 1/4.
             ℹ Connection closed unexpectedly

This is not a transient network blip. The connection is closed because
the payload is too large or the response takes too long to stream.
Retrying with the same payload will fail the same way, which is why you
see all retry attempts fail in sequence.

### Fix: bound the context window

Use the built-in `reducer_last_n(n)` in your schema:

``` r
# Keep only the last 6 messages — enough context, bounded payload
runner <- debate_workflow(
  agents = list(
    pro = agent("pro", chat_anthropic()),
    con = agent("con", chat_anthropic())
  ),
  max_rounds   = 6L,
  state_schema = workflow_state(
    messages      = list(default = list(), reducer = reducer_last_n(6L)),
    judge_verdict = list(default = "continue")
  )
)
```

As a rough guide, keep the sliding window at 2–3× the number of agents
so each agent can always see its own previous turn and the most recent
responses from others.

### What to keep vs. discard

Not all channels need the same strategy:

| Channel type            | Recommended reducer                                                                              | Reason                                          |
|-------------------------|--------------------------------------------------------------------------------------------------|-------------------------------------------------|
| Conversation history    | `reducer_last_n(n)`                                                                              | Bounds payload; recent context is most relevant |
| Accumulated results     | [`reducer_append()`](https://arnold-kakas.github.io/puppeteeR/reference/reducer_append.md)       | You want all results for the final evaluator    |
| Routing signals         | [`reducer_overwrite()`](https://arnold-kakas.github.io/puppeteeR/reference/reducer_overwrite.md) | Only the current value matters                  |
| Running score / counter | [`reducer_overwrite()`](https://arnold-kakas.github.io/puppeteeR/reference/reducer_overwrite.md) | Single scalar, always replaced                  |

## Sizing `max_turns` correctly

`max_turns(n)` counts **total node executions** — every agent call and
every dispatcher call combined. It is easy to set too low.

### Per workflow

| Workflow              | Formula                                                | Example                                    |
|-----------------------|--------------------------------------------------------|--------------------------------------------|
| `sequential_workflow` | `length(agents)`                                       | 3 agents → `max_turns(3)`                  |
| `supervisor_workflow` | `n_workers × expected_delegations × 2 + buffer`        | 2 workers, 3 delegations → `max_turns(16)` |
| `debate_workflow`     | `max_rounds × length(agents)` (set internally)         | Handled automatically                      |
| `advisor_workflow`    | `2 × (max_revisions + 1)` (set internally)             | Handled automatically                      |
| `planner_workflow`    | `(max_replans + 1) × (max_steps + 3)` (set internally) | Handled automatically                      |

For custom graphs, add a buffer of at least 20–30% over your minimum
expected turns to account for extra routing steps and retries.

### Composing termination conditions

For production workflows, combine `max_turns` with a cost ceiling:

``` r
schema <- workflow_state(result = list(default = NULL))

runner <- state_graph(schema) |>
  add_node("worker", function(state, config) list()) |>
  add_edge(START, "worker") |>
  add_edge("worker", END) |>
  compile(
    agents      = list(worker = analyst),
    termination = max_turns(50L) | cost_limit(2.00)
  )
```

The workflow stops as soon as either condition is met. See
[`?max_turns`](https://arnold-kakas.github.io/puppeteeR/reference/max_turns.md),
[`?cost_limit`](https://arnold-kakas.github.io/puppeteeR/reference/cost_limit.md),
[`?text_match`](https://arnold-kakas.github.io/puppeteeR/reference/text_match.md),
and
[`?custom_condition`](https://arnold-kakas.github.io/puppeteeR/reference/custom_condition.md)
for all available conditions.

## Resilience

### Use a checkpointer for any long workflow

The runner saves state after every successful node. If a later node
fails — whether from a connection error, API timeout, or a bug —
re-invoking with the same `thread_id` resumes from the last saved state
automatically. No work is lost.

``` r
cp <- rds_checkpointer("checkpoints/")   # survives session restarts

result <- runner$invoke(
  initial_state = list(messages = list("Produce an article on quantum computing.")),
  config = list(
    thread_id    = "article-run-01",
    checkpointer = cp,
    verbose      = TRUE
  )
)

# If it fails partway through, re-run the identical call:
result <- runner$invoke(
  initial_state = list(messages = list("Produce an article on quantum computing.")),
  config = list(
    thread_id    = "article-run-01",
    checkpointer = cp
  )
)
# Prints: "Resuming from checkpoint at step N."
```

Use
[`memory_checkpointer()`](https://arnold-kakas.github.io/puppeteeR/reference/memory_checkpointer.md)
during development (no files written), `rds_checkpointer(dir)` for
single-machine persistence, and `sqlite_checkpointer(path)` when you
need to inspect or query checkpoint history. See
[`vignette("checkpointing")`](https://arnold-kakas.github.io/puppeteeR/articles/checkpointing.md).

### Set retry parameters on agents

The default is `max_retries = 3L` (4 total attempts) with
`retry_wait = 5` seconds. For workflows where agents receive large
contexts — or when calling during peak API hours — increase the wait:

``` r
worker <- agent(
  "worker",
  chat_anthropic(model = "claude-haiku-4-5-20251001"),
  max_retries = 5L,
  retry_wait  = 15
)
```

Note: if all retry attempts fail with “Connection closed unexpectedly”,
the cause is almost always context size, not a transient network issue.
Increase `retry_wait` only after addressing context bounds first.

## Prompt design

### Supervisor manager

The manager’s routing relies on text-matching its response against
worker names. Vague or multi-worker responses will fall through to
`"DONE"` unexpectedly.

``` r
manager <- agent(
  "manager",
  chat_anthropic(model = "claude-opus-4-6"),
  instructions = paste0(
    "You coordinate a research team.\n\n",
    "Available workers:\n",
    "  - 'researcher': finds and summarises sources\n",
    "  - 'writer': turns notes into prose\n\n",
    "On each turn, reply with ONLY one worker name to delegate to, ",
    "or ONLY the word 'DONE' when the task is complete. ",
    "Do not add any other text to your routing reply."
  )
)
```

### Advisor

The advisor routes on `startsWith("approved")`. Any response not
starting with `"approved"` triggers a revision regardless of content.
Use the `"revise: <feedback>"` convention so the feedback passed back to
the worker is clean:

``` r
advisor <- agent(
  "advisor",
  chat_anthropic(model = "claude-opus-4-6"),
  instructions = paste0(
    "You are a strict quality reviewer.\n\n",
    "If the response fully answers the task with no factual errors, reply exactly:\n",
    "  approved\n\n",
    "Otherwise reply:\n",
    "  revise: <one paragraph of specific, actionable feedback>\n\n",
    "Start your reply with either 'approved' or 'revise:' — no other prefix."
  )
)
```

### Planner

The default parser expects one step per line in
`worker_name: instruction` format. Instruct the planner to avoid
preamble and numbered lists:

``` r
planner <- agent(
  "planner",
  chat_anthropic(model = "claude-opus-4-6"),
  instructions = paste0(
    "You decompose tasks into steps for a team of workers.\n\n",
    "Available workers: 'researcher', 'writer'.\n\n",
    "Respond with ONLY the plan — one step per line, format:\n",
    "  worker_name: instruction\n\n",
    "No numbering, no preamble, no blank lines between steps."
  )
)
```

## Observability

### Live step logging

``` r
result <- runner$invoke(
  initial_state = list(messages = list("Write a report.")),
  config = list(
    verbose = TRUE,       # prints "[1] researcher done.", "[2] writer done.", etc.
    on_step = function(node, state) {
      cat(sprintf("After %s — messages: %d\n",
                  node, length(state$get("messages"))))
    }
  )
)
```

### Cost report

``` r
runner$cost_report()
#   agent      provider   model                      input_tokens output_tokens  cost
# 1 planner    Anthropic  claude-opus-4-6                    2341          892  0.042
# 2 researcher Anthropic  claude-haiku-4-5-20251001           891          234  0.001
# 3 writer     Anthropic  claude-haiku-4-5-20251001           743          412  0.001
```

### Graph visualisation

Check the graph structure before running — especially useful after
building a custom graph to confirm edges are wired as intended:

``` r
runner$visualize("dot")        # interactive Graphviz widget
runner$visualize("visnetwork") # interactive force-directed graph
runner$as_mermaid()            # paste into mermaid.live
```

See
[`vignette("visualization")`](https://arnold-kakas.github.io/puppeteeR/articles/visualization.md)
for full details.
