test_that("invoke() returns WorkflowState", {
  schema <- workflow_state(result = list(default = ""))
  runner <- state_graph(schema) |>
    add_node("work", function(state, config) list(result = "done")) |>
    add_edge(START, "work") |>
    add_edge("work", END) |>
    compile()

  final <- runner$invoke()
  expect_true(inherits(final, "WorkflowState"))
  expect_equal(final$get("result"), "done")
})

test_that("invoke() respects initial_state overrides", {
  schema <- workflow_state(x = list(default = 0L))
  runner <- state_graph(schema) |>
    add_node("n", function(state, config) list(x = state$get("x") * 2L)) |>
    add_edge(START, "n") |>
    add_edge("n", END) |>
    compile()

  final <- runner$invoke(list(x = 5L))
  expect_equal(final$get("x"), 10L)
})

test_that("invoke() stops at max_iterations", {
  schema <- workflow_state(n = list(default = 0L))

  runner <- state_graph(schema) |>
    add_node("loop", function(state, config) list(n = state$get("n") + 1L)) |>
    add_edge(START, "loop") |>
    add_edge("loop", "loop") |>
    compile(termination = max_turns(100L))

  final <- runner$invoke(config = list(max_iterations = 5L))
  expect_equal(final$get("n"), 5L)
})

test_that("on_step callback is invoked", {
  schema <- workflow_state(x = list(default = 0L))
  calls  <- character(0)

  runner <- state_graph(schema) |>
    add_node("a", function(state, config) list(x = 1L)) |>
    add_edge(START, "a") |>
    add_edge("a", END) |>
    compile()

  runner$invoke(config = list(on_step = function(node, state) {
    calls <<- c(calls, node)
  }))

  expect_equal(calls, "a")
})

test_that("termination condition stops early", {
  schema <- workflow_state(n = list(default = 0L))

  runner <- state_graph(schema) |>
    add_node("loop", function(state, config) list(n = state$get("n") + 1L)) |>
    add_edge(START, "loop") |>
    add_edge("loop", "loop") |>
    compile(termination = max_turns(3L))

  final <- runner$invoke(config = list(max_iterations = 100L))
  expect_equal(final$get("n"), 3L)
})

test_that("cost_report() returns a data frame", {
  schema <- workflow_state(x = list(default = 0L))
  runner <- state_graph(schema) |>
    add_node("n", function(state, config) list(x = 1L)) |>
    add_edge(START, "n") |>
    add_edge("n", END) |>
    compile()

  report <- runner$cost_report()
  expect_s3_class(report, "data.frame")
})

test_that("retry_policy() rejects bad arguments", {
  expect_error(retry_policy(max_attempts = 1L),  "max_attempts")
  expect_error(retry_policy(wait_seconds = -1),  "wait_seconds")
  expect_error(retry_policy(backoff = 0),        "backoff")
})

test_that("node with retry succeeds after transient failures", {
  attempt_n <- 0L
  flaky_fn  <- function(state, config) {
    attempt_n <<- attempt_n + 1L
    if (attempt_n < 3L) stop("transient error")
    list(result = "ok")
  }

  schema <- workflow_state(result = list(default = ""))
  runner <- state_graph(schema) |>
    add_node("flaky", flaky_fn, retry = retry_policy(max_attempts = 3L, wait_seconds = 0)) |>
    add_edge(START, "flaky") |>
    add_edge("flaky", END) |>
    compile()

  final <- runner$invoke()
  expect_equal(final$get("result"), "ok")
  expect_equal(attempt_n, 3L)
})

test_that("node exhausts retries and throws with attempt count", {
  always_fail <- function(state, config) stop("permanent failure")

  schema <- workflow_state(x = list(default = 0L))
  runner <- state_graph(schema) |>
    add_node("bad", always_fail, retry = retry_policy(max_attempts = 2L, wait_seconds = 0)) |>
    add_edge(START, "bad") |>
    add_edge("bad", END) |>
    compile()

  expect_error(runner$invoke(), "2 attempt")
})

test_that("node without retry still wraps error with node name", {
  schema <- workflow_state(x = list(default = 0L))
  runner <- state_graph(schema) |>
    add_node("boom", function(state, config) stop("kaboom")) |>
    add_edge(START, "boom") |>
    add_edge("boom", END) |>
    compile()

  expect_error(runner$invoke(), "boom")
})

test_that("add_node() rejects non-retry_policy retry argument", {
  schema <- workflow_state(x = list(default = 0L))
  g <- state_graph(schema)
  expect_error(
    g$add_node("n", function(state, config) list(), retry = list(max_attempts = 3L)),
    "retry_policy"
  )
})

test_that("on_event fires node_start and node_end for each node", {
  schema <- workflow_state(x = list(default = 0L))
  events <- list()

  runner <- state_graph(schema) |>
    add_node("a", function(state, config) list(x = 1L)) |>
    add_node("b", function(state, config) list(x = 2L)) |>
    add_edge(START, "a") |>
    add_edge("a", "b") |>
    add_edge("b", END) |>
    compile()

  runner$invoke(config = list(on_event = function(event) {
    events[[length(events) + 1L]] <<- event
  }))

  types <- vapply(events, `[[`, character(1), "type")
  nodes <- vapply(events, `[[`, character(1), "node")

  expect_equal(types, c("node_start", "node_end", "node_start", "node_end"))
  expect_equal(nodes, c("a", "a", "b", "b"))
})

test_that("on_event node_end carries state updates", {
  schema <- workflow_state(result = list(default = ""))
  end_events <- list()

  runner <- state_graph(schema) |>
    add_node("work", function(state, config) list(result = "done")) |>
    add_edge(START, "work") |>
    add_edge("work", END) |>
    compile()

  runner$invoke(config = list(on_event = function(event) {
    if (event$type == "node_end") end_events[[length(end_events) + 1L]] <<- event
  }))

  expect_length(end_events, 1L)
  expect_equal(end_events[[1L]]$data$updates$result, "done")
})

test_that("on_event iteration counter is correct", {
  schema <- workflow_state(n = list(default = 0L))
  iters <- integer(0)

  runner <- state_graph(schema) |>
    add_node("step", function(state, config) list(n = state$get("n") + 1L)) |>
    add_edge(START, "step") |>
    add_edge("step", END) |>
    compile()

  runner$invoke(config = list(on_event = function(event) {
    if (event$type == "node_start") iters <<- c(iters, event$iteration)
  }))

  expect_equal(iters, 1L)
})

test_that("on_event NULL causes no overhead (invoke still works)", {
  schema <- workflow_state(x = list(default = 0L))
  runner <- state_graph(schema) |>
    add_node("n", function(state, config) list(x = 99L)) |>
    add_edge(START, "n") |>
    add_edge("n", END) |>
    compile()

  final <- runner$invoke()
  expect_equal(final$get("x"), 99L)
})

## --- interrupt tests ---------------------------------------------------

make_log_graph <- function(cp, interrupt_before = character(),
                                interrupt_after  = character()) {
  schema <- workflow_state(log = list(default = list(), reducer = reducer_append()))
  state_graph(schema) |>
    add_node("a", function(state, config) list(log = "a")) |>
    add_node("b", function(state, config) list(log = "b")) |>
    add_node("c", function(state, config) list(log = "c")) |>
    add_edge(START, "a") |>
    add_edge("a", "b") |>
    add_edge("b", "c") |>
    add_edge("c", END) |>
    compile(checkpointer = cp,
            interrupt_before = interrupt_before,
            interrupt_after  = interrupt_after)
}

test_that("interrupt_before pauses before the named node", {
  cp     <- memory_checkpointer()
  runner <- make_log_graph(cp, interrupt_before = "b")

  state1 <- runner$invoke(config = list(thread_id = "t1"))
  expect_equal(state1$get("log"), list("a"))
})

test_that("second invoke() resumes and completes after interrupt_before", {
  cp     <- memory_checkpointer()
  runner <- make_log_graph(cp, interrupt_before = "b")

  runner$invoke(config = list(thread_id = "t1"))
  state2 <- runner$invoke(config = list(thread_id = "t1"))

  expect_equal(state2$get("log"), list("a", "b", "c"))
})

test_that("interrupt_before fires again on a re-visit in a cyclic graph", {
  cp     <- memory_checkpointer()
  schema <- workflow_state(n = list(default = 0L))
  runner <- state_graph(schema) |>
    add_node("step", function(state, config) list(n = state$get("n") + 1L)) |>
    add_edge(START, "step") |>
    add_edge("step", "step") |>
    compile(checkpointer = cp, termination = max_turns(10L),
            interrupt_before = "step")

  runner$invoke(config = list(thread_id = "c1"))           # pauses before step (n = 0)
  runner$invoke(config = list(thread_id = "c1"))           # executes step (n = 1) then pauses again
  state3 <- runner$invoke(config = list(thread_id = "c1")) # executes step (n = 2) then pauses again

  expect_equal(state3$get("n"), 2L)
})

test_that("update_state() changes are visible when resumed after interrupt_before", {
  cp     <- memory_checkpointer()
  schema <- workflow_state(
    value  = list(default = "original"),
    result = list(default = "")
  )
  runner <- state_graph(schema) |>
    add_node("gate",  function(state, config) list()) |>
    add_node("read",  function(state, config) list(result = state$get("value"))) |>
    add_edge(START, "gate") |>
    add_edge("gate", "read") |>
    add_edge("read", END) |>
    compile(checkpointer = cp, interrupt_before = "gate")

  runner$invoke(config = list(thread_id = "t1"))
  runner$update_state("t1", list(value = "modified"))
  state2 <- runner$invoke(config = list(thread_id = "t1"))

  expect_equal(state2$get("result"), "modified")
})

test_that("interrupt_after pauses after the named node", {
  cp     <- memory_checkpointer()
  runner <- make_log_graph(cp, interrupt_after = "b")

  state1 <- runner$invoke(config = list(thread_id = "t1"))
  expect_equal(state1$get("log"), list("a", "b"))
})

test_that("second invoke() resumes and completes after interrupt_after", {
  cp     <- memory_checkpointer()
  runner <- make_log_graph(cp, interrupt_after = "b")

  runner$invoke(config = list(thread_id = "t1"))
  state2 <- runner$invoke(config = list(thread_id = "t1"))

  expect_equal(state2$get("log"), list("a", "b", "c"))
})

test_that("interrupt_before on entry node pauses immediately", {
  cp     <- memory_checkpointer()
  runner <- make_log_graph(cp, interrupt_before = "a")

  state1 <- runner$invoke(config = list(thread_id = "t1"))
  expect_equal(state1$get("log"), list())

  state2 <- runner$invoke(config = list(thread_id = "t1"))
  expect_equal(state2$get("log"), list("a", "b", "c"))
})

test_that("compile() requires a checkpointer when interrupt_before is set", {
  schema <- workflow_state(x = list(default = 0L))
  g <- state_graph(schema) |>
    add_node("n", function(state, config) list(x = 1L)) |>
    add_edge(START, "n") |>
    add_edge("n", END)

  expect_error(compile(g, interrupt_before = "n"), "Checkpointer")
})

test_that("compile() rejects unknown node names in interrupt_before", {
  cp     <- memory_checkpointer()
  schema <- workflow_state(x = list(default = 0L))
  g <- state_graph(schema) |>
    add_node("n", function(state, config) list(x = 1L)) |>
    add_edge(START, "n") |>
    add_edge("n", END)

  expect_error(compile(g, checkpointer = cp, interrupt_before = "missing"), "missing")
})

test_that("invoke() without thread_id errors when interrupts are configured", {
  cp     <- memory_checkpointer()
  schema <- workflow_state(x = list(default = 0L))
  runner <- state_graph(schema) |>
    add_node("n", function(state, config) list(x = 1L)) |>
    add_edge(START, "n") |>
    add_edge("n", END) |>
    compile(checkpointer = cp, interrupt_before = "n")

  expect_error(runner$invoke(), "thread_id")
})

test_that("get_state() strips interrupt metadata from returned snapshot", {
  cp     <- memory_checkpointer()
  runner <- make_log_graph(cp, interrupt_before = "b")

  runner$invoke(config = list(thread_id = "t1"))
  snap <- runner$get_state("t1")

  expect_false(any(startsWith(names(snap), ".")))
})

## --- stream tests -------------------------------------------------------

test_that("stream() yields node results", {
  schema <- workflow_state(
    n = list(default = 0L, reducer = function(old, new) old + new)
  )
  runner <- state_graph(schema) |>
    add_node("a", function(state, config) list(n = 1L)) |>
    add_node("b", function(state, config) list(n = 1L)) |>
    add_edge(START, "a") |>
    add_edge("a", "b") |>
    add_edge("b", END) |>
    compile()

  gen   <- runner$stream()
  step1 <- gen()
  step2 <- gen()

  expect_false(coro::is_exhausted(step1))
  expect_false(coro::is_exhausted(step2))
  expect_true(coro::is_exhausted(gen()))
  expect_equal(step1$node, "a")
  expect_equal(step2$node, "b")
})
