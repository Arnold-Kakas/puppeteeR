test_that("max_turns triggers at correct iteration", {
  cond <- max_turns(5L)
  expect_false(check_termination(cond, NULL, 4L, 0))
  expect_true(check_termination(cond, NULL, 5L, 0))
  expect_true(check_termination(cond, NULL, 6L, 0))
})

test_that("cost_limit triggers when exceeded", {
  cond <- cost_limit(1.00)
  expect_false(check_termination(cond, NULL, 1L, 0.99))
  expect_true(check_termination(cond, NULL, 1L, 1.00))
})

test_that("text_match triggers on pattern presence", {
  ws <- workflow_state(status = list(default = ""))
  cond <- text_match("DONE", channel = "status")
  ws$set("status", "Task DONE")
  expect_true(check_termination(cond, ws, 1L, 0))
  ws$set("status", "still running")
  expect_false(check_termination(cond, ws, 1L, 0))
})

test_that("custom_condition evaluates user function", {
  ws <- workflow_state(flag = list(default = FALSE))
  cond <- custom_condition(function(state) isTRUE(state$get("flag")))
  expect_false(check_termination(cond, ws, 1L, 0))
  ws$set("flag", TRUE)
  expect_true(check_termination(cond, ws, 1L, 0))
})

test_that("| combines conditions with OR", {
  a <- max_turns(3L)
  b <- cost_limit(1.00)
  combined <- a | b

  expect_false(check_termination(combined, NULL, 2L, 0.5))
  expect_true(check_termination(combined, NULL, 3L, 0.5))
  expect_true(check_termination(combined, NULL, 2L, 1.0))
})

test_that("& combines conditions with AND", {
  a <- max_turns(3L)
  b <- max_turns(5L)
  combined <- a & b

  expect_false(check_termination(combined, NULL, 3L, 0))
  expect_false(check_termination(combined, NULL, 4L, 0))
  expect_true(check_termination(combined, NULL, 5L, 0))
})

test_that("max_turns errors on invalid n", {
  expect_error(max_turns(0L), regexp = "positive")
  expect_error(max_turns(-1L), regexp = "positive")
})
