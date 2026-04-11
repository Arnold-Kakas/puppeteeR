# Checkpointing and Human-in-the-Loop

Checkpointing lets you persist workflow state after every node
execution. This enables:

- **Resuming interrupted runs** — restart after a crash without losing
  completed work
- **Human-in-the-loop** — pause, inspect, modify state, then resume
- **Auditing** — inspect state at any step in the run history

## Checkpointer types

| Class                | Where state lives    | Best for                          |
|----------------------|----------------------|-----------------------------------|
| `MemoryCheckpointer` | RAM                  | Dev, testing, short sessions      |
| `RDSCheckpointer`    | `.rds` files on disk | Long runs, multi-session          |
| `SQLiteCheckpointer` | SQLite database      | Concurrent threads, query history |

## How checkpointing actually works

Understanding the mechanics saves debugging time.

**Saving:** After each node executes, the runner calls
`checkpointer$save(thread_id, step, state$snapshot())`. Step 1 is saved
after the first node completes, step 2 after the second, and so on. The
snapshot is a plain named list of all channel values at that moment.

**Resuming:** When `invoke()` is called again with a known `thread_id`,
the runner:

1.  Creates a fresh state from the schema defaults.
2.  Loads the latest checkpoint: `checkpointer$load_latest(thread_id)`.
3.  Calls `state$restore(snapshot)` — this writes the saved values
    directly into the state, bypassing reducers.
4.  Sets `start_step` to the last saved step number, so subsequent saves
    don’t overwrite history.
5.  **Starts executing from the entry node (first node in the graph)**.
    There is no automatic node-skipping; execution always begins at the
    start.

The practical implication: **resumed nodes re-execute, but they find the
state already populated**. Nodes designed to overwrite their output
channel will replace it with a (likely identical) new value. Nodes that
accumulate into an `append` reducer will add to the already-restored
list. See the [Idempotent node patterns](#idempotent-node-patterns)
section for how to handle this.

## Thread IDs — your crash recovery handle

Every checkpointed run is identified by a `thread_id` string that you
supply. There is no auto-generated ID — you own it.

**Strategy:** make thread IDs meaningful and predictable from context
you already have:

``` r
# Good: derive from the input data
thread_id <- paste0("report-", format(Sys.Date(), "%Y%m%d"))
thread_id <- paste0("file-", tools::file_path_sans_ext(basename(input_file)))
thread_id <- paste0("user-", user_id, "-task-", task_id)

# Also fine for interactive sessions
thread_id <- "my-experiment-v2"
```

If a crash happens and you didn’t store the ID, you can recover it:

``` r
cp <- rds_checkpointer(path = "checkpoints/")

# See every thread that has at least one checkpoint
cp$list_threads()
#> [1] "file-report_2024_q1"  "file-report_2024_q2"  "user-42-task-7"
```

For SQLite you can also query the database directly:

``` r
cp <- sqlite_checkpointer(path = "workflow.sqlite")
cp$list_threads()
```

## Basic usage

Pass a checkpointer to
[`compile()`](https://arnold-kakas.github.io/puppeteeR/reference/compile.md)
and a `thread_id` to `invoke()`.

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

## Crash scenario: what exactly happens

Here is a step-by-step walkthrough of a crash and recovery using an RDS
checkpointer.

``` r
cp <- rds_checkpointer(path = "checkpoints/")

schema <- workflow_state(
  status  = list(default = ""),
  result  = list(default = "")
)

runner <- state_graph(schema) |>
  add_node("fetch", function(state, config) {
    # Imagine this reads from a database or API
    list(status = "fetched", result = "raw data")
  }) |>
  add_node("process", function(state, config) {
    # This is the expensive LLM call that might time out
    result <- config$agents$llm$chat(state$get("result"))
    list(status = "processed", result = result)
  }) |>
  add_node("save", function(state, config) {
    # Write result to disk / database
    writeLines(state$get("result"), "output.txt")
    list(status = "saved")
  }) |>
  add_edge(START, "fetch") |>
  add_edge("fetch", "process") |>
  add_edge("process", "save") |>
  add_edge("save", END) |>
  compile(agents = list(llm = my_agent), checkpointer = cp)
```

**Run 1 — partial success, then crash:**

``` r
tryCatch(
  runner$invoke(list(), config = list(thread_id = "job-99")),
  error = function(e) message("Run failed: ", conditionMessage(e))
)
# "fetch" completed  → checkpoint saved: step=1, status="fetched"
# "process" threw a network timeout → no checkpoint written for step 2
# Run failed: ...
```

At this point the checkpoint directory contains:

    checkpoints/
      job-99/
        step_1.rds    ← state after "fetch" completed

**Inspect the checkpoint to understand where things stand:**

``` r
cp$list_threads()
#> [1] "job-99"

cp$load_latest("job-99")
#> $step
#> [1] 1
#>
#> $state
#> $state$status
#> [1] "fetched"
#>
#> $state$result
#> [1] "raw data"
```

**Run 2 — resume with the same thread_id:**

``` r
# No initial_state needed — it comes from the checkpoint
runner$invoke(config = list(thread_id = "job-99", verbose = TRUE))
# Resuming from checkpoint at step 1.
# [1] fetch done.
# [2] process done.
# [3] save done.
```

Notice that `fetch` re-executes. With
[`reducer_overwrite()`](https://arnold-kakas.github.io/puppeteeR/reference/reducer_overwrite.md)
channels (the default for scalars), this just replaces `status` and
`result` with the same values — harmless. But see the next section for
when that is not the case.

## Idempotent node patterns

Because execution always restarts from the first node, nodes that do
expensive or stateful work should guard against redundant re-execution.

**Pattern 1 — skip if output is already set (overwrite channels):**

``` r
fetch_node <- function(state, config) {
  if (nzchar(state$get("result"))) return(list())   # already fetched

  raw <- httr2::request("https://api.example.com/data") |>
    httr2::req_perform() |>
    httr2::resp_body_string()
  list(result = raw, status = "fetched")
}
```

This node returns an empty list (no update) when `result` is already
populated, so it is a no-op on resume.

**Pattern 2 — guard with a status flag:**

``` r
process_node <- function(state, config) {
  if (state$get("status") == "processed") return(list())

  answer <- config$agents$llm$chat(state$get("result"))
  list(result = answer, status = "processed")
}
```

**Pattern 3 — be careful with
[`reducer_append()`](https://arnold-kakas.github.io/puppeteeR/reference/reducer_append.md):**

Append reducers accumulate on every call. If a node appends to a
messages channel and is re-run on resume, it will append again to the
already-restored list:

``` r
# This node is NOT safe to re-run after checkpoint restore
log_node <- function(state, config) {
  list(messages = "step complete")   # appends every time
}

# Safe version — guard with a marker in the messages list
log_node_safe <- function(state, config) {
  msgs <- state$get("messages")
  if (any(vapply(msgs, identical, logical(1L), "step complete"))) return(list())
  list(messages = "step complete")
}
```

Alternatively, use
[`reducer_overwrite()`](https://arnold-kakas.github.io/puppeteeR/reference/reducer_overwrite.md)
for channels that nodes compute fresh and do not need history.

## RDS checkpointer — survives across R sessions

``` r
cp <- rds_checkpointer(path = "~/my_checkpoints")

runner <- state_graph(schema) |>
  add_node("step1", function(s, cfg) {
    if (s$get("status") == "step1-done") return(list())
    Sys.sleep(2)   # simulate slow work
    list(counter = s$get("counter") + 1L, status = "step1-done")
  }) |>
  add_node("step2", function(s, cfg) {
    if (s$get("status") == "step2-done") return(list())
    list(counter = s$get("counter") * 2L, status = "step2-done")
  }) |>
  add_edge(START, "step1") |>
  add_edge("step1", "step2") |>
  add_edge("step2", END) |>
  compile(checkpointer = cp)

# Session 1 — crashes after step1
runner$invoke(list(counter = 5L, status = ""), config = list(thread_id = "job-42"))

# Session 2 (new R process) — re-create runner, then resume
runner$invoke(config = list(thread_id = "job-42"))
# step1 finds status == "step1-done" → returns list(), no-op
# step2 runs fresh → counter = 6 * 2 = 12
```

Files are written as `~/my_checkpoints/job-42/step_1.rds`, `step_2.rds`,
etc.

## SQLite checkpointer — multiple threads

``` r
cp <- sqlite_checkpointer(path = "workflow.sqlite")

# Run two independent threads against the same compiled runner
runner$invoke(list(counter = 1L), config = list(thread_id = "thread-A"))
runner$invoke(list(counter = 100L), config = list(thread_id = "thread-B"))

cp$list_threads()
#> [1] "thread-A" "thread-B"

# Inspect specific steps
cp$load_step(thread_id = "thread-A", step = 1L)
cp$load_latest("thread-B")
```

## Human-in-the-loop

Use `update_state()` to manually edit checkpointed state before
resuming. The runner treats the edit as one additional checkpoint step
and resumes from the modified state.

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
    # Skip if we already have a draft that was not rejected
    if (nzchar(state$get("draft")) && !nzchar(state$get("feedback"))) return(list())

    task <- if (nzchar(state$get("feedback"))) {
      paste0(
        "Original draft:\n", state$get("draft"),
        "\n\nFeedback:\n", state$get("feedback"),
        "\n\nPlease revise."
      )
    } else {
      state$get("task")
    }
    list(draft = config$agents$writer$chat(task), feedback = "")
  }) |>
  add_node("check_approval", function(state, config) {
    list()   # gate node — routes based on human-set `approved` flag
  }) |>
  add_conditional_edge(
    "check_approval",
    routing_fn = function(s) if (isTRUE(s$get("approved"))) "done" else "revise",
    route_map  = list(done = END, revise = "write")
  ) |>
  add_edge(START, "write") |>
  add_edge("write", "check_approval") |>
  compile(agents = list(writer = writer), checkpointer = cp)

# Step 1: run — produces a draft, parks at check_approval, then routes to "write"
# (approved is FALSE by default, so it loops back)
runner$invoke(
  list(task = "Explain gradient descent."),
  config = list(thread_id = "review-1")
)

# Step 2: human reads the draft
draft <- runner$get_state("review-1")$draft
cat(draft)

# Step 3a: human is not satisfied — inject feedback and resume
runner$update_state("review-1", list(
  feedback = "Too abstract. Use a concrete analogy.",
  approved = FALSE
))
runner$invoke(config = list(thread_id = "review-1"))

# Step 3b: human approves — mark it and resume to finish
runner$update_state("review-1", list(approved = TRUE, feedback = ""))
runner$invoke(config = list(thread_id = "review-1"))
runner$get_state("review-1")$draft
```

**What `update_state()` does internally:** 1. Loads the latest
checkpoint for the thread. 2. Applies the updates to the snapshot (no
reducers — direct replacement). 3. Saves a new checkpoint at
`last_step + 1`.

When `invoke()` is next called, it loads this new checkpoint and resumes
with your edits in place.

## Step callbacks

The `on_step` callback fires after each node, giving you a lightweight
way to observe progress without a full checkpointer.

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

## Resilient batch pipelines

When processing many files, two failure modes matter:

- **Within a run**: the API call in node 3 fails after nodes 1 and 2
  already ran. Without a checkpoint you re-run the expensive steps from
  scratch.
- **Across runs**: the pipeline crashes on item 7 of 20. You want to
  skip items 1–6 on retry.

Combine a checkpointer (within-run resilience) with a done-file tracker
(across-run resilience). Design each node to be idempotent so
re-execution on resume is harmless:

``` r
library(ellmer)

schema <- workflow_state(
  file_path    = list(default = ""),
  file_content = list(default = ""),
  llm_result   = list(default = ""),
  status       = list(default = "")
)

cp <- rds_checkpointer(path = "checkpoints/")

runner <- state_graph(schema) |>
  add_node("read_file", function(s, cfg) {
    if (nzchar(s$get("file_content"))) return(list())   # already read
    list(
      file_content = readLines(s$get("file_path"), warn = FALSE) |> paste(collapse = "\n"),
      status = "read"
    )
  }) |>
  add_node("call_llm", function(s, cfg) {
    if (s$get("status") == "processed") return(list())  # already processed
    result <- cfg$agents$llm$chat(s$get("file_content"))
    list(llm_result = result, status = "processed")
  }) |>
  add_node("save_result", function(s, cfg) {
    if (s$get("status") == "saved") return(list())      # already saved
    out <- file.path("output", basename(s$get("file_path")))
    writeLines(s$get("llm_result"), out)
    list(status = "saved")
  }) |>
  add_edge(START, "read_file") |>
  add_edge("read_file",   "call_llm") |>
  add_edge("call_llm",    "save_result") |>
  add_edge("save_result", END) |>
  compile(agents = list(llm = my_agent), checkpointer = cp)

files     <- list.files("source", pattern = "\\.txt$", full.names = TRUE)
done_file <- "checkpoints/done.rds"
done      <- if (file.exists(done_file)) readRDS(done_file) else character(0)

for (f in setdiff(files, done)) {
  thread_id <- paste0("file-", tools::file_path_sans_ext(basename(f)))
  message("Processing: ", basename(f))
  tryCatch({
    runner$invoke(
      list(file_path = f),
      config = list(thread_id = thread_id)
    )
    done <- c(done, f)
    saveRDS(done, done_file)
  }, error = function(e) {
    message("  FAILED: ", conditionMessage(e), " — will retry next run")
  })
}
```

**Failure and recovery walkthrough:**

| Event                                   | What happens                                                                                          |
|-----------------------------------------|-------------------------------------------------------------------------------------------------------|
| `read_file` completes                   | Checkpoint saved: `step=1`, `status="read"`                                                           |
| `call_llm` hits a timeout               | No checkpoint for step 2; loop catches the error                                                      |
| Next run starts                         | `done.rds` does not contain this file → it is retried                                                 |
| `invoke()` called with same `thread_id` | Checkpoint loaded, state restored: `status="read"`                                                    |
| `read_file` re-runs                     | Guard fires: `file_content` already set → returns [`list()`](https://rdrr.io/r/base/list.html), no-op |
| `call_llm` re-runs                      | Guard fires: `status != "processed"` → runs the LLM call for real                                     |
| Success                                 | `done.rds` updated; file is skipped on all future runs                                                |

## Listing and loading specific steps

``` r
cp <- sqlite_checkpointer(path = "workflow.sqlite")

# All threads
cp$list_threads()

# Load state at a specific step (useful for auditing)
cp$load_step(thread_id = "job-42", step = 2L)

# Load the most recent state
cp$load_latest("job-42")
```
