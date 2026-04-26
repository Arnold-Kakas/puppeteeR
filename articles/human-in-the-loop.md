# Human-in-the-Loop Interrupts

Node-level interrupts let you pause a running graph at a named node,
hand control back to R code (or a person), optionally edit the state,
and then resume from exactly where you left off.

They are the right tool when you need a **deliberate, structured gate**
in a workflow - a point where a human must approve, correct, or annotate
before the graph continues. They are not the right tool for every
situation; the last section of this vignette explains when to reach for
something simpler instead.

## How interrupts work

    compile(interrupt_before = "review")

    invoke() call 1             invoke() call 2
    -----------                 -----------
    START                       (checkpoint restored)
      |                               |
      v                               v
    writer  <-- runs               review  <-- resumes here, runs now
      |                               |
      v                               v
    review  <-- PAUSE              publish
      |
      (returns current state)

Two flags are available at
[`compile()`](https://arnold-kakas.github.io/puppeteeR/reference/compile.md)
time:

| Flag                        | When the pause fires                                                                     |
|-----------------------------|------------------------------------------------------------------------------------------|
| `interrupt_before = "node"` | Before `"node"` executes - state reflects everything up to (but not including) that node |
| `interrupt_after = "node"`  | After `"node"` executes - state includes that node’s output                              |

Both require a checkpointer and a `thread_id` in every `invoke()`
config - they use the checkpoint to know where to re-enter on the next
call.

## Minimal working example

``` r
cp <- memory_checkpointer()

schema <- workflow_state(
  draft    = list(default = ""),
  approved = list(default = FALSE)
)

runner <- state_graph(schema) |>
  add_node("write",   function(state, config) list(draft = "first draft text")) |>
  add_node("review",  function(state, config) list()) |>
  add_node("publish", function(state, config) {
    cat("Publishing:", state$get("draft"), "\n")
    list()
  }) |>
  add_edge(START, "write") |>
  add_edge("write", "review") |>
  add_edge("review", "publish") |>
  add_edge("publish", END) |>
  compile(checkpointer = cp, interrupt_before = "review")
```

**First invoke - runs `write`, then pauses before `review`:**

``` r
state1 <- runner$invoke(config = list(thread_id = "demo"))
state1$get("draft")     # written by "write", visible to the human now
#> [1] "first draft text"
state1$get("approved")  # still the default
#> [1] FALSE
```

The human inspects the draft and updates state:

``` r
runner$update_state("demo", list(
  draft    = "revised draft text",
  approved = TRUE
))
```

**Second invoke with the same thread_id - resumes from `review`:**

``` r
state2 <- runner$invoke(config = list(thread_id = "demo"))
#> Publishing: revised draft text
state2$get("draft")
#> [1] "revised draft text"
```

## interrupt_before vs. interrupt_after

Use **`interrupt_before`** when you want the human to influence what a
node does - to set inputs, parameters, or flags that the node reads:

``` r
cp1 <- memory_checkpointer()

schema1 <- workflow_state(
  topic    = list(default = ""),
  tone     = list(default = "neutral"),   # human may override this
  article  = list(default = "")
)

runner1 <- state_graph(schema1) |>
  add_node("write", function(state, config) {
    prompt <- paste0("Write about: ", state$get("topic"),
                     ". Tone: ", state$get("tone"), ".")
    list(article = paste("[article with tone:", state$get("tone"), "]"))
  }) |>
  add_edge(START, "write") |>
  add_edge("write", END) |>
  compile(checkpointer = cp1, interrupt_before = "write")

# Pause before "write" fires - human adjusts the tone
runner1$invoke(list(topic = "renewable energy"),
               config = list(thread_id = "t1"))
#> WorkflowState with 3 channel(s):
#> topic: chr "renewable energy"
#> tone: chr "neutral"
#> article: chr ""

runner1$update_state("t1", list(tone = "optimistic"))
final1 <- runner1$invoke(config = list(thread_id = "t1"))
final1$get("article")
#> [1] "[article with tone: optimistic ]"
```

Use **`interrupt_after`** when you want the human to review and possibly
correct what a node produced before the workflow continues:

``` r
cp2 <- memory_checkpointer()

schema2 <- workflow_state(
  data    = list(default = ""),
  summary = list(default = "")
)

runner2 <- state_graph(schema2) |>
  add_node("summarise", function(state, config) {
    list(summary = paste("Summary of:", state$get("data")))
  }) |>
  add_node("store", function(state, config) {
    cat("Storing summary:", state$get("summary"), "\n")
    list()
  }) |>
  add_edge(START, "summarise") |>
  add_edge("summarise", "store") |>
  add_edge("store", END) |>
  compile(checkpointer = cp2, interrupt_after = "summarise")

# "summarise" runs, then pauses so human can correct the output
runner2$invoke(list(data = "raw input"),
               config = list(thread_id = "t2"))
#> WorkflowState with 2 channel(s):
#> data: chr "raw input"
#> summary: chr "Summary of: raw input"
runner2$get_state("t2")$summary
#> [1] "Summary of: raw input"

runner2$update_state("t2", list(summary = "corrected summary"))
runner2$invoke(config = list(thread_id = "t2"))
#> Storing summary: corrected summary
#> WorkflowState with 2 channel(s):
#> data: chr "raw input"
#> summary: chr "corrected summary"
```

## Production patterns

### Content approval gate

A writer agent drafts content; a human approves or requests revisions
before it goes to the publisher.

``` r
library(ellmer)

cp <- rds_checkpointer(path = "checkpoints/")

schema <- workflow_state(
  brief    = list(default = ""),
  draft    = list(default = ""),
  feedback = list(default = ""),
  status   = list(default = "pending")
)

writer    <- agent("writer",    chat_anthropic(), instructions = "Write marketing copy.")
publisher <- agent("publisher", chat_anthropic(), instructions = "Reformat for publication.")

runner <- state_graph(schema) |>
  add_node("draft", function(state, config) {
    brief    <- state$get("brief")
    feedback <- state$get("feedback")

    prompt <- if (nzchar(feedback)) {
      paste0("Brief: ", brief, "\n\nRevision feedback: ", feedback,
             "\n\nPlease revise the draft.")
    } else {
      paste0("Write copy for: ", brief)
    }
    list(draft = config$agents$writer$chat(prompt), feedback = "")
  }) |>
  add_node("publish", function(state, config) {
    formatted <- config$agents$publisher$chat(
      paste0("Format for publication:\n", state$get("draft"))
    )
    list(status = "published", draft = formatted)
  }) |>
  add_edge(START, "draft") |>
  add_edge("draft", "publish") |>
  add_edge("publish", END) |>
  compile(
    agents         = list(writer = writer, publisher = publisher),
    checkpointer   = cp,
    interrupt_after = "draft"   # pause after draft is ready, before publishing
  )

# --- run 1: draft is produced ---
thread_id <- paste0("campaign-", format(Sys.Date(), "%Y%m%d"))
runner$invoke(list(brief = "Launch of new product X"), config = list(thread_id = thread_id))

# --- human reviews ---
snap <- runner$get_state(thread_id)
cat(snap$draft)

# Option A: approve and continue
runner$invoke(config = list(thread_id = thread_id))

# Option B: request a revision
runner$update_state(thread_id, list(
  feedback = "Too salesy. Keep it factual.",
  draft    = ""   # reset so the draft node re-runs
))
# But wait - the interrupt was interrupt_after = "draft", so next invoke
# will resume AFTER draft, skipping to "publish". To loop back, restructure
# the graph with a conditional edge instead (see the "When not to use" section).
```

### Compliance sign-off

Some workflows must not proceed until a named individual has authorised
a step. Store the `thread_id` in your database so anyone can pick up the
review later - even in a different R session.

``` r
cp <- sqlite_checkpointer(path = "compliance.sqlite")

# Persist the thread_id alongside the request record in your own database:
# db_insert("reviews", list(request_id = req_id, thread_id = thread_id, status = "pending"))

runner <- state_graph(schema) |>
  add_node("analyse",  analyse_fn) |>
  add_node("escalate", escalate_fn) |>
  add_node("execute",  execute_fn) |>
  add_edge(START, "analyse") |>
  add_edge("analyse", "escalate") |>
  add_edge("escalate", "execute") |>
  add_edge("execute", END) |>
  compile(checkpointer = cp, interrupt_before = "execute")

# In a later R session (e.g. when the reviewer logs in):
# runner$update_state(thread_id, list(approved_by = "alice@example.com"))
# runner$invoke(config = list(thread_id = thread_id))
```

### Multiple gates in one graph

You can list several nodes in `interrupt_before` or `interrupt_after`.
Execution pauses at each one in turn; each resume advances to the next
gate.

``` r
cp3 <- memory_checkpointer()
schema3 <- workflow_state(log = list(default = list(), reducer = reducer_append()))

runner3 <- state_graph(schema3) |>
  add_node("draft",    function(s, cfg) list(log = "drafted")) |>
  add_node("legal",    function(s, cfg) list(log = "legal checked")) |>
  add_node("finance",  function(s, cfg) list(log = "finance checked")) |>
  add_node("publish",  function(s, cfg) list(log = "published")) |>
  add_edge(START, "draft") |>
  add_edge("draft",   "legal") |>
  add_edge("legal",   "finance") |>
  add_edge("finance", "publish") |>
  add_edge("publish", END) |>
  compile(checkpointer = cp3, interrupt_before = c("legal", "finance", "publish"))

# invoke 1: runs "draft", pauses before "legal"
s1 <- runner3$invoke(config = list(thread_id = "multi"))
s1$get("log")
#> [[1]]
#> [1] "drafted"

# invoke 2: runs "legal", pauses before "finance"
s2 <- runner3$invoke(config = list(thread_id = "multi"))
s2$get("log")
#> [[1]]
#> [1] "drafted"
#> 
#> [[2]]
#> [1] "legal checked"

# invoke 3: runs "finance", pauses before "publish"
s3 <- runner3$invoke(config = list(thread_id = "multi"))
s3$get("log")
#> [[1]]
#> [1] "drafted"
#> 
#> [[2]]
#> [1] "legal checked"
#> 
#> [[3]]
#> [1] "finance checked"

# invoke 4: runs "publish", reaches END
s4 <- runner3$invoke(config = list(thread_id = "multi"))
s4$get("log")
#> [[1]]
#> [1] "drafted"
#> 
#> [[2]]
#> [1] "legal checked"
#> 
#> [[3]]
#> [1] "finance checked"
#> 
#> [[4]]
#> [1] "published"
```

## Checkpointer choice in production

Memory checkpointer is only suitable for interactive experimentation -
it does not survive process restarts. For anything real:

| Scenario                                   | Checkpointer          | Why                      |
|--------------------------------------------|-----------------------|--------------------------|
| Single-user scripts that run to completion | `rds_checkpointer`    | Simple, no dependencies  |
| Long jobs across multiple R sessions       | `rds_checkpointer`    | Files persist on disk    |
| Multiple threads, concurrent reviews       | `sqlite_checkpointer` | Atomic writes, queryable |
| Shiny app where users resume workflows     | `sqlite_checkpointer` | One database, many users |

Keep thread IDs in your own database or records alongside the item being
processed. That way you can always reconnect to a paused workflow even
after a restart.

## When NOT to use interrupts

Interrupts add round-trips and require a checkpointer. Before reaching
for them, consider whether a simpler primitive covers your case.

**Use a conditional edge instead** when the routing decision is already
available in state and does not need a human. A routing function reading
an `approved` channel is lighter than a full interrupt cycle:

``` r
cp4 <- memory_checkpointer()
schema4 <- workflow_state(
  draft    = list(default = ""),
  approved = list(default = FALSE)
)

runner4 <- state_graph(schema4) |>
  add_node("draft",   function(s, cfg) list(draft = "output")) |>
  add_node("publish", function(s, cfg) { cat("published\n"); list() }) |>
  add_node("revise",  function(s, cfg) list(draft = "revised output", approved = TRUE)) |>
  add_edge(START, "draft") |>
  add_conditional_edge(
    "draft",
    routing_fn = function(s) if (isTRUE(s$get("approved"))) "publish" else "revise",
    route_map  = list(publish = "publish", revise = "revise")
  ) |>
  add_edge("revise",  "draft") |>
  add_edge("publish", END) |>
  compile(
    checkpointer = cp4,
    termination  = max_turns(10L)
  )

runner4$invoke(config = list(thread_id = "cond-demo"))
#> published
#> WorkflowState with 2 channel(s):
#> draft: chr "output"
#> approved: logi TRUE
```

**Use `update_state()` without interrupts** when you want to manually
edit state between two complete runs. This is what the
[`vignette("checkpointing")`](https://arnold-kakas.github.io/puppeteeR/articles/checkpointing.md)
describes - it is simpler when you do not need mid-graph pausing.

**Use `on_event` instead** when you just want to observe what the graph
is doing without ever pausing it. An event callback has zero overhead
and does not require a checkpointer:

``` r
schema5 <- workflow_state(x = list(default = 0L))
runner5 <- state_graph(schema5) |>
  add_node("a", function(s, cfg) list(x = 1L)) |>
  add_node("b", function(s, cfg) list(x = 2L)) |>
  add_edge(START, "a") |>
  add_edge("a", "b") |>
  add_edge("b", END) |>
  compile()

runner5$invoke(config = list(
  on_event = function(event) {
    if (event$type == "node_end")
      cat(sprintf("  %s done\n", event$node))
  }
))
#>   a done
#>   b done
#> WorkflowState with 1 channel(s):
#> x: int 2
```

**Do not use interrupts in fully automated pipelines.** If no human will
actually act between the pause and the resume, you are adding latency
and complexity for nothing. Interrupts only make sense when a person (or
an external system) is genuinely involved in the loop.

**Do not interrupt on every node.** Treat interrupt points like
production checkpoints in a factory - too many and the line slows to a
crawl. Identify the one or two points where a real decision must be made
and interrupt only there.

## Summary

| Need                                      | Tool                                   |
|-------------------------------------------|----------------------------------------|
| Pause before a node; human sets inputs    | `interrupt_before`                     |
| Pause after a node; human corrects output | `interrupt_after`                      |
| Route based on human-set flag             | conditional edge reading state         |
| Observe without pausing                   | `on_event` callback                    |
| Edit state between complete runs          | `update_state()` (no interrupt needed) |
| Recover from crashes automatically        | checkpointing + idempotent nodes       |

## See also

- [`vignette("checkpointing")`](https://arnold-kakas.github.io/puppeteeR/articles/checkpointing.md) -
  how checkpointing and `update_state()` work
- [`vignette("event-streaming")`](https://arnold-kakas.github.io/puppeteeR/articles/event-streaming.md) -
  `on_event` for observability without pausing
- [`?compile`](https://arnold-kakas.github.io/puppeteeR/reference/compile.md) -
  full reference for `interrupt_before` and `interrupt_after`
