# State Channels and Reducers

`WorkflowState` is the shared memory that all nodes in a graph read from
and write to. This vignette explains how it works, what reducers do, and
how to design your state schema for different workflow patterns.

## Two layers of memory

Before diving into state channels, it’s important to understand that
puppeteeR has **two independent memory systems** that coexist:

**1. WorkflowState channels** — explicit, inspectable, structured. This
is what nodes read with `state$get()` and write by returning named
lists. You control it entirely via your schema.

**2. ellmer Chat conversation history** — implicit, per-agent. Each
`Agent` wraps an
[`ellmer::Chat`](https://ellmer.tidyverse.org/reference/Chat.html)
object, which maintains its own internal turn-by-turn history. Every
time you call `agent$chat("hello")`, ellmer appends the exchange to that
Chat’s history. The agent “remembers” prior calls at the LLM level
regardless of what the WorkflowState contains.

These two systems do not automatically synchronise. A practical
consequence: if you reset or restore a WorkflowState from a checkpoint,
the agents’ internal Chat histories are unaffected. For most workflows
this is fine. For workflows that fork or replay from checkpoints, you
may need to reset agent Chat objects manually (using
`agent$chat_object$set_turns(list())`).

## Channels and reducers

A `WorkflowState` is defined by a **schema** — a named list where each
entry is a channel:

``` r
ws <- workflow_state(
  messages = list(default = list(), reducer = reducer_append()),
  status   = list(default = "pending"),
  metadata = list(default = list(), reducer = reducer_merge())
)
```

Each channel has:

- `default` — the value the channel holds before any node writes to it.
- `reducer` — a two-argument function `function(old, new)` that decides
  how an incoming update is merged with the current value. If omitted,
  the default depends on the channel type: `reducer_last_n(20)` for list
  channels (`default = list(...)`) and
  [`reducer_overwrite()`](https://arnold-kakas.github.io/puppeteeR/reference/reducer_overwrite.md)
  for all other channels.

When a node returns an update, `state$update()` applies the reducer for
each key:

``` r
# Node returns:
list(status = "done", messages = "All finished.")

# Internally, for each key:
new_value <- reducer(current_value, incoming_value)
```

The reducer is called on **every write**, not just the first. This is
what makes channels behave differently depending on their reducer.

## Built-in reducers

### `reducer_overwrite()` — replace (default)

``` r
r <- reducer_overwrite()
r("old value", "new value")
#> [1] "new value"
```

The current value is discarded and replaced with the new one. This is
the default when no `reducer` is specified. Use it for scalar state:
status flags, routing signals, counters, the current draft of a
document.

### `reducer_append()` — accumulate a list

``` r
r <- reducer_append()
r(list("first"), "second")
#> [[1]]
#> [1] "first"
#> 
#> [[2]]
#> [1] "second"
```

The incoming value is wrapped in
[`list()`](https://rdrr.io/r/base/list.html) and concatenated to the
existing list. Use this for any channel that should **accumulate**
entries over time — conversation history, log entries, collected
results.

> **Warning:**
> [`reducer_append()`](https://arnold-kakas.github.io/puppeteeR/reference/reducer_append.md)
> grows unboundedly. For long-running workflows, consider trimming
> strategies — e.g. keeping only the last N messages, or summarising
> older turns.

### `reducer_merge()` — shallow list merge

``` r
r <- reducer_merge()
r(list(model = "haiku", temp = 0.7), list(temp = 0.2, seed = 42))
#> $model
#> [1] "haiku"
#> 
#> $temp
#> [1] 0.2
#> 
#> $seed
#> [1] 42
```

Uses [`modifyList()`](https://rdrr.io/r/utils/modifyList.html) to merge
the incoming named list into the existing one. Keys in `new` overwrite
matching keys in `old`; keys absent from `new` are preserved. Use for
nested configuration or metadata that is updated piecemeal.

## Designing your schema

### Pattern 1: append for history, overwrite for signals

The most common pattern for multi-turn workflows:

``` r
state_schema <- workflow_state(
  messages      = list(default = list(), reducer = reducer_append()),
  current_route = list(default = "")
)
```

`messages` accumulates the full conversation. `current_route` is a
transient routing signal — only the most recent value matters, so
overwrite is correct.

### Pattern 2: separate draft from history

When you want agents to revise output without polluting the message
history:

``` r
state_schema <- workflow_state(
  messages     = list(default = list(), reducer = reducer_append()),
  latest_draft = list(default = ""),
  revision_n   = list(default = 0L)
)
```

Worker nodes write their output to `latest_draft` (overwrite — always
the current version). An advisor node reads `latest_draft`, not
`messages`. Approved drafts can then be moved to `messages` at the end.
This is the recommended pattern for advisor/revision workflows.

### Pattern 3: dedicated verdict channel

When a routing decision needs to survive across nodes without being
confused with message content:

``` r
state_schema <- workflow_state(
  messages       = list(default = list(), reducer = reducer_append()),
  judge_verdict  = list(default = "continue")
)
```

The judge node writes `list(judge_verdict = "done")`. The conditional
routing function reads `state$get("judge_verdict")` directly — no
text-scanning the last message required.

## What the default schema does NOT give you

The `messages` channel with
[`reducer_append()`](https://arnold-kakas.github.io/puppeteeR/reference/reducer_append.md)
gives agents a shared history that grows over time. But the convenience
workflow constructors (`supervisor_workflow`, `sequential_workflow`,
`debate_workflow`) do **not** automatically pass the full history to
every node. Their built-in node functions vary:

| Workflow                      | What the node passes to the LLM            |
|-------------------------------|--------------------------------------------|
| `sequential_workflow`         | Last message only (`msgs[[length(msgs)]]`) |
| `supervisor_workflow` manager | Full history concatenated                  |
| `supervisor_workflow` workers | Last message only                          |
| `debate_workflow` debaters    | Full history concatenated                  |
| `debate_workflow` judge       | Full history concatenated                  |

If your supervisor workers need full context (e.g. a writer needs to see
what the researcher found), you have two options:

**Option A** — pass full context in the node function:

``` r
writer_fn <- function(state, config) {
  msgs    <- state$get("messages")
  context <- paste(vapply(msgs, as.character, character(1)), collapse = "\n")
  response <- config$agents$writer$chat(context)
  list(messages = response)
}
```

**Option B** — rely on ellmer’s internal Chat history. Because the
manager already passed full context to the LLM in its turn, and the
worker’s Chat object accumulates its own history, the worker agent may
already “know” prior content if it was involved in earlier turns.
However, this only works for the same agent across multiple calls — a
worker agent that is called for the first time has no prior context.

For most supervisor workflows, Option A is safer and more predictable.

## Bugs fixed in the built-in workflows

Two fragilities existed in the original convenience constructors. Both
are fixed; this section explains what was wrong and how the fixes work —
both for understanding the design and as examples of how to design state
correctly in your own workflows.

### Fix 1: supervisor workers now receive full context

**What was wrong.** Worker node functions in `supervisor_workflow`
passed only the *last* message to the LLM:

``` r
last <- msgs[[length(msgs)]]
response <- config$agents[[worker_nm]]$chat(as.character(last))
```

This meant a writer worker had no idea what the researcher already found
— it only saw the manager’s most recent delegation instruction.

**Why it matters.** The supervisor pattern assumes workers are
specialists that execute specific instructions. But meaningful
instructions usually reference earlier context (“write a conclusion
based on the research above”). Without full context, workers produce
responses that are contextually blind.

**The fix.** Workers now concatenate the full message history, identical
to how the manager node already worked:

``` r
context  <- paste(vapply(msgs, as.character, character(1L)), collapse = "\n")
response <- config$agents[[worker_nm]]$chat(context)
```

### Fix 2: debate judge routing now uses a dedicated channel

**What was wrong.** The judge node returned
`list(messages = verdict, .judge_verdict = verdict)`. Because keys
prefixed with `"."` are silently ignored by `state$update()`, the
`.judge_verdict` key was **never written**. The routing function then
read the last entry from `messages` and searched it for the word “done”
— which happened to work only because the judge was always the last node
to run.

This was fragile: any future refactoring that appended to `messages`
after the judge node would silently break routing.

**The fix.** The default schema now includes a `judge_verdict` channel:

``` r
state_schema <- workflow_state(
  messages      = list(default = list(), reducer = reducer_append()),
  judge_verdict = list(default = "continue")   # new
)
```

The judge node normalises and writes the verdict explicitly:

``` r
verdict_str   <- tolower(trimws(as.character(verdict)))
judge_verdict <- if (grepl("done", verdict_str, fixed = TRUE)) "done" else "continue"
list(messages = verdict, judge_verdict = judge_verdict)
```

The routing function reads from the channel directly — no text scanning:

``` r
g$add_conditional_edge("judge", function(state) state$get("judge_verdict"), route_map)
```

**General principle.** Never route based on the last item in an
accumulating channel. Use a dedicated overwrite channel for every
routing signal so the routing function is a clean
`state$get("signal_name")` with no fragile text parsing.

## Custom reducers

You can supply any two-argument function as a reducer:

``` r
reducer_max <- function() {
  function(old, new) max(old, new, na.rm = TRUE)
}

state_schema <- workflow_state(
  messages   = list(default = list(), reducer = reducer_last_n(10L)),
  best_score = list(default = 0,      reducer = reducer_max())
)
```

`reducer_last_n(n)` is a built-in reducer that keeps only the most
recent `n` entries. It is particularly useful for long-running
supervisor or debate workflows where you want to prevent the context
window from growing too large. `reducer_max` above is an example of a
fully custom reducer.

## Snapshot and restore

`WorkflowState$snapshot()` returns a plain named list — a point-in-time
copy of all channel values. This is what checkpointers persist, and what
`$restore()` reads back.

``` r
ws <- workflow_state(
  messages = list(default = list(), reducer = reducer_append()),
  status   = list(default = "pending")
)

ws$update(list(messages = "hello", status = "running"))
snap <- ws$snapshot()
# snap is a plain list — safe to saveRDS(), serialize(), etc.

ws$update(list(messages = "world"))
ws$restore(snap)  # rolls back to the post-"hello" state
```

Note that `$restore()` **bypasses reducers** — it directly overwrites
channel values with the snapshot contents. This is intentional:
restoration should reproduce the exact prior state, not merge into it.

## New workflow patterns

### `advisor_workflow()` — worker + advisor feedback loop

Pairs a cheap worker model with an expensive advisor model. The advisor
evaluates the draft and either approves it or sends it back for
revision. The state schema uses separate channels for the draft
(overwrite — always the current version) and the message history (append
— full audit trail):

``` r
# Default schema used internally by advisor_workflow()
state_schema <- workflow_state(
  messages         = list(default = list(), reducer = reducer_append()),
  latest_draft     = list(default = ""),         # current worker output
  advisor_feedback = list(default = ""),         # advisor's revision notes
  advisor_verdict  = list(default = "revise"),   # routing signal
  revision_n       = list(default = 0L)          # revision counter
)
```

`latest_draft` uses
[`reducer_overwrite()`](https://arnold-kakas.github.io/puppeteeR/reference/reducer_overwrite.md)
so it always holds the most recent attempt — not a growing list of all
drafts. The advisor reads `latest_draft`, not `messages`, which keeps
the evaluation focused on the current version.

``` r
library(ellmer)

runner <- advisor_workflow(
  worker  = agent("writer",  chat_anthropic(model = "claude-haiku-4-5-20251001"),
                  instructions = "Write clearly and concisely."),
  advisor = agent("advisor", chat_anthropic(model = "claude-opus-4-6"),
                  instructions = "Enforce strict quality standards."),
  max_revisions = 3L
)

result <- runner$invoke(list(messages = list("Explain what a closure is in R.")))
result$get("latest_draft")   # final approved text
result$get("revision_n")     # how many revisions were needed
```

Graph structure:

    START -> worker -> advisor -> approved -> END
                               -> revise   -> worker (up to max_revisions times)

The advisor prompt instructs the model to reply with either `"approved"`
or `"revise: <feedback>"`. The routing function reads `advisor_verdict`
directly — no text scanning involved.

### `planner_workflow()` — Opus plans, Haiku executes

Separates the expensive planning/evaluation work (Opus) from the cheap
execution work (Haiku). The key design is a **pure-R dispatcher node**
that routes plan steps without making any LLM calls — only the planner
and evaluator consume expensive tokens per round.

``` r
# Default schema used internally by planner_workflow()
state_schema <- workflow_state(
  messages            = list(default = list(), reducer = reducer_append()),
  plan                = list(default = list(), reducer = reducer_overwrite()),  # replaced wholesale on each planner turn
  plan_index          = list(default = 0L),              # dispatcher cursor
  current_instruction = list(default = ""),              # active step instruction
  current_worker      = list(default = ""),              # active step worker
  results             = list(default = list(), reducer = reducer_append()),
  evaluator_verdict   = list(default = ""),
  replan_count        = list(default = 0L)
)
```

`plan_index` is an overwrite counter that the dispatcher increments on
each call. When `plan_index > length(plan)`, the dispatcher routes to
the evaluator (or END if no evaluator was supplied). This is purely R
logic — zero LLM tokens spent on routing.

``` r
runner <- planner_workflow(
  planner   = agent("planner",    chat_anthropic(model = "claude-opus-4-6"),
                    instructions  = "Break tasks into steps for 'researcher' and 'writer'."),
  workers   = list(
    researcher = agent("researcher", chat_anthropic(model = "claude-haiku-4-5-20251001")),
    writer     = agent("writer",     chat_anthropic(model = "claude-haiku-4-5-20251001"))
  ),
  evaluator  = agent("evaluator", chat_anthropic(model = "claude-opus-4-6")),
  max_replans = 2L,
  max_steps   = 6L
)

result <- runner$invoke(list(messages = list("Write a short report on tidy data principles.")))
result$get("results")   # list of all worker outputs
```

The planner must respond with one step per line:
`worker_name: instruction`. A custom `parse_plan` function can be
supplied for alternative formats (e.g. JSON):

``` r
parse_json_plan <- function(text) {
  steps <- jsonlite::fromJSON(as.character(text))
  lapply(seq_len(nrow(steps)), function(i) {
    list(worker = steps$worker[[i]], instruction = steps$instruction[[i]])
  })
}

runner <- planner_workflow(
  planner    = agent("planner", chat_anthropic(model = "claude-opus-4-6")),
  workers    = list(analyst = agent("analyst", chat_anthropic())),
  parse_plan = parse_json_plan
)
```

Graph structure:

    START -> planner -> dispatcher -> worker_A ─┐
                                  -> worker_B ─┤-> dispatcher (loop until plan exhausted)
                                  -> evaluator -> done   -> END
                                              -> replan -> planner

**Cost profile.** For a plan with N steps and R replanning rounds:

| Model            | Calls         |
|------------------|---------------|
| Opus (planner)   | `R + 1`       |
| Opus (evaluator) | `R + 1`       |
| Haiku (workers)  | `N × (R + 1)` |

Compared to `supervisor_workflow` where the manager (Opus) is called
once per step, the planner workflow calls Opus only once per planning
round regardless of how many steps the plan contains.
