test_that("workflow_state creates channels with defaults", {
  ws <- workflow_state(
    x = list(default = 0L),
    y = list(default = "hello")
  )
  expect_equal(ws$get("x"), 0L)
  expect_equal(ws$get("y"), "hello")
})

test_that("reducer_overwrite replaces value", {
  ws <- workflow_state(x = list(default = 1L))
  ws$set("x", 99L)
  expect_equal(ws$get("x"), 99L)
})

test_that("reducer_append accumulates values", {
  ws <- workflow_state(
    msgs = list(default = list(), reducer = reducer_append())
  )
  ws$set("msgs", "a")
  ws$set("msgs", "b")
  expect_equal(ws$get("msgs"), list("a", "b"))
})

test_that("reducer_merge merges lists", {
  ws <- workflow_state(
    cfg = list(default = list(a = 1L, b = 2L), reducer = reducer_merge())
  )
  ws$set("cfg", list(b = 99L, c = 3L))
  expect_equal(ws$get("cfg"), list(a = 1L, b = 99L, c = 3L))
})

test_that("update() applies multiple changes at once", {
  ws <- workflow_state(
    x = list(default = 0L),
    y = list(default = "")
  )
  ws$update(list(x = 5L, y = "new"))
  expect_equal(ws$get("x"), 5L)
  expect_equal(ws$get("y"), "new")
})

test_that("update() ignores dot-prefixed keys", {
  ws <- workflow_state(x = list(default = 0L))
  expect_no_error(ws$update(list(x = 1L, .internal = "ignored")))
})

test_that("update() errors on unknown channel", {
  ws <- workflow_state(x = list(default = 0L))
  expect_error(ws$update(list(unknown = 1L)), regexp = "Unknown channel")
})

test_that("snapshot() and restore() round-trip", {
  ws <- workflow_state(
    a = list(default = 42L),
    b = list(default = "hi")
  )
  snap <- ws$snapshot()
  ws$set("a", 99L)
  ws$restore(snap)
  expect_equal(ws$get("a"), 42L)
})

test_that("keys() returns channel names", {
  ws <- workflow_state(x = list(default = 1L), y = list(default = 2L))
  expect_setequal(ws$keys(), c("x", "y"))
})

test_that("get() errors on missing channel", {
  ws <- workflow_state(x = list(default = 1L))
  expect_error(ws$get("nope"), regexp = "not in the workflow state")
})
