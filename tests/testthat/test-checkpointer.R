test_that("MemoryCheckpointer save/load_latest round-trips", {
  cp <- memory_checkpointer()
  snap <- list(x = 1L, y = "hello")
  cp$save("thread1", 1L, snap)
  result <- cp$load_latest("thread1")
  expect_equal(result$step, 1L)
  expect_equal(result$state, snap)
})

test_that("MemoryCheckpointer load_latest returns latest step", {
  cp <- memory_checkpointer()
  cp$save("t", 1L, list(x = 1L))
  cp$save("t", 3L, list(x = 3L))
  cp$save("t", 2L, list(x = 2L))
  result <- cp$load_latest("t")
  expect_equal(result$step, 3L)
  expect_equal(result$state$x, 3L)
})

test_that("MemoryCheckpointer load_latest returns NULL for unknown thread", {
  cp <- memory_checkpointer()
  expect_null(cp$load_latest("nonexistent"))
})

test_that("MemoryCheckpointer load_step retrieves exact step", {
  cp <- memory_checkpointer()
  cp$save("t", 1L, list(val = "step1"))
  cp$save("t", 2L, list(val = "step2"))
  result <- cp$load_step("t", 1L)
  expect_equal(result$val, "step1")
})

test_that("MemoryCheckpointer list_threads returns thread IDs", {
  cp <- memory_checkpointer()
  cp$save("alpha", 1L, list())
  cp$save("beta",  1L, list())
  threads <- cp$list_threads()
  expect_setequal(threads, c("alpha", "beta"))
})

test_that("RDSCheckpointer save/load_latest round-trips", {
  dir <- tempfile()
  cp <- rds_checkpointer(dir)
  snap <- list(x = 42L)
  cp$save("run1", 1L, snap)
  result <- cp$load_latest("run1")
  expect_equal(result$step, 1L)
  expect_equal(result$state, snap)
})

test_that("RDSCheckpointer list_threads works", {
  dir <- tempfile()
  cp <- rds_checkpointer(dir)
  cp$save("t1", 1L, list())
  cp$save("t2", 1L, list())
  expect_setequal(cp$list_threads(), c("t1", "t2"))
})

test_that("GraphRunner checkpoints and restores state", {
  schema <- workflow_state(
    n = list(default = 0L)
  )
  cp <- memory_checkpointer()

  runner <- state_graph(schema) |>
    add_node("inc", function(state, config) list(n = state$get("n") + 1L)) |>
    add_edge(START, "inc") |>
    add_edge("inc", END) |>
    compile(checkpointer = cp)

  runner$invoke(list(n = 0L), config = list(thread_id = "my_run"))
  saved <- cp$load_latest("my_run")
  expect_false(is.null(saved))
  expect_equal(saved$state$n, 1L)
})
