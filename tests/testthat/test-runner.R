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
