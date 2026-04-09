# Checkpointing and Human-in-the-Loop

Checkpointing lets you persist workflow state after every node
execution. This enables:

- **Resuming interrupted runs** — restart after a crash without
  re-running completed nodes
- **Human-in-the-loop** — pause, inspect, modify state, then resume
- **Auditing** — replay state at any step

## Checkpointer types

| Class                | Where state lives    | Best for                          |
|----------------------|----------------------|-----------------------------------|
| `MemoryCheckpointer` | RAM                  | Dev, testing, short sessions      |
| `RDSCheckpointer`    | `.rds` files on disk | Long runs, multi-session          |
| `SQLiteCheckpointer` | SQLite database      | Concurrent threads, query history |

## Basic usage

Pass a checkpointer to [`compile()`](../reference/compile.md) and a
`thread_id` to `invoke()`.

``` r
cp <- memory_checkpointer()

schema <- workflow_state(
  counter = list(default = 0L),
  log     = list(default = list(), reducer = reducer_append())
)

runner <- state_graph(schema) |>
  add_node("inc", function(state, config) {
    n <- state$get("counter")
    list(counter = n + 1L, log = paste0("incremented to ", n + 1L))
  }) |>
  add_edge(START, "inc") |>
  add_edge("inc", END) |>
  compile(checkpointer = cp)

runner$invoke(list(counter = 0L), config = list(thread_id = "demo"))
#> WorkflowState with 2 channel(s):
#> counter: int 1
#> log: List of 1 $ : chr "incremented to 1"

# Retrieve the last checkpoint
runner$get_state("demo")
#> $counter
#> [1] 1
#> 
#> $log
#> $log[[1]]
#> [1] "incremented to 1"
```

## RDS checkpointer — survives across sessions

``` r
cp <- rds_checkpointer(dir = "~/my_checkpoints")

runner <- state_graph(schema) |>
  add_node("step1", function(s, cfg) list(counter = s$get("counter") + 1L)) |>
  add_node("step2", function(s, cfg) list(counter = s$get("counter") * 2L)) |>
  add_edge(START, "step1") |>
  add_edge("step1", "step2") |>
  add_edge("step2", END) |>
  compile(checkpointer = cp)

# Run 1 — say it crashes mid-way
runner$invoke(list(counter = 5L), config = list(thread_id = "job-42"))

# Run 2 — restart; runner resumes from last saved checkpoint
runner$invoke(config = list(thread_id = "job-42"))
```

Files are written as `~/my_checkpoints/job-42/step_1.rds`, `step_2.rds`,
etc.

## SQLite checkpointer — multiple threads

``` r
cp <- sqlite_checkpointer("workflow.sqlite")

# List all threads with saved state
cp$list_threads()

# Run two independent threads against the same compiled runner
runner$invoke(list(counter = 1L), config = list(thread_id = "thread-A"))
runner$invoke(list(counter = 100L), config = list(thread_id = "thread-B"))

cp$list_threads()  # "thread-A" "thread-B"
```

## Human-in-the-loop

Use `update_state()` to manually edit checkpointed state before resuming
a run. This is useful when a human needs to review or correct an agent’s
output mid-workflow.

``` r
review_schema <- workflow_state(
  task     = list(default = ""),
  draft    = list(default = ""),
  approved = list(default = FALSE),
  feedback = list(default = "")
)
```

``` r
library(ellmer)

writer <- agent("writer", chat_anthropic(),
                instructions = "Write a short paragraph on the given task.")

cp <- memory_checkpointer()

runner <- state_graph(review_schema) |>
  add_node("write", function(state, config) {
    draft <- config$agents$writer$chat(state$get("task"))
    list(draft = draft)
  }) |>
  add_node("check_approval", function(state, config) {
    list()   # gate node — routes based on human-set `approved` flag
  }) |>
  add_node("revise", function(state, config) {
    prompt <- paste0(
      "Original draft:\n", state$get("draft"),
      "\n\nFeedback:\n", state$get("feedback"),
      "\n\nPlease revise."
    )
    list(draft = config$agents$writer$chat(prompt))
  }) |>
  add_edge(START, "write") |>
  add_edge("write", "check_approval") |>
  add_conditional_edge(
    "check_approval",
    routing_fn = function(s) if (isTRUE(s$get("approved"))) "done" else "revise",
    route_map  = list(done = END, revise = "revise")
  ) |>
  add_edge("revise", END) |>
  compile(agents = list(writer = writer), checkpointer = cp)

# Step 1: run until the gate
runner$invoke(
  list(task = "Explain gradient descent."),
  config = list(thread_id = "review-1")
)

# Step 2: human reviews the draft
draft <- runner$get_state("review-1")$draft
cat(draft)

# Step 3: human injects feedback (or approves)
runner$update_state("review-1", list(
  approved = FALSE,
  feedback = "Too abstract. Use a concrete analogy."
))

# Step 4: resume — runner picks up from the checkpoint
runner$invoke(config = list(thread_id = "review-1"))
runner$get_state("review-1")$draft
```

## Step callbacks

The `on_step` callback fires after each node, giving you a lightweight
alternative to checkpointing when you just need to observe progress.

``` r
schema <- workflow_state(n = list(default = 0L))

runner <- state_graph(schema) |>
  add_node("a", function(s, cfg) list(n = s$get("n") + 1L)) |>
  add_node("b", function(s, cfg) list(n = s$get("n") * 10L)) |>
  add_edge(START, "a") |>
  add_edge("a", "b") |>
  add_edge("b", END) |>
  compile()

runner$invoke(
  list(n = 3L),
  config = list(
    verbose = TRUE,
    on_step = function(node, state) {
      cat(sprintf("  after %-10s  n = %d\n", node, state$get("n")))
    }
  )
)
#> [1] a done.
#>   after a           n = 4
#> [2] b done.
#>   after b           n = 40
#> WorkflowState with 1 channel(s):
#> n: int 40
```

## Listing and loading specific steps

``` r
cp <- sqlite_checkpointer("workflow.sqlite")

# All threads
cp$list_threads()

# Load state at a specific step
cp$load_step(thread_id = "job-42", step = 2L)

# Load the most recent state
cp$load_latest("job-42")
```
