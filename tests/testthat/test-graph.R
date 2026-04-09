make_simple_graph <- function() {
  schema <- workflow_state(result = list(default = NULL))
  state_graph(schema) |>
    add_node("a", function(state, config) list(result = "a_done")) |>
    add_edge(START, "a") |>
    add_edge("a", END)
}

test_that("state_graph() creates a StateGraph", {
  schema <- workflow_state(x = list(default = 0L))
  g <- state_graph(schema)
  expect_s3_class(g, "R6")
  expect_true(inherits(g, "StateGraph"))
})

test_that("add_node() registers a node", {
  schema <- workflow_state(x = list(default = 0L))
  g <- state_graph(schema)
  g$add_node("node1", function(state, config) list())
  expect_no_error(g$add_edge(START, "node1"))
  expect_no_error(g$add_edge("node1", END))
})

test_that("duplicate node name errors", {
  schema <- workflow_state(x = list(default = 0L))
  g <- state_graph(schema)
  g$add_node("node1", function(state, config) list())
  expect_error(g$add_node("node1", function(state, config) list()), "already exists")
})

test_that("add_edge() errors when from has existing fixed edge", {
  schema <- workflow_state(x = list(default = 0L))
  g <- state_graph(schema) |>
    add_node("a", function(state, config) list()) |>
    add_node("b", function(state, config) list()) |>
    add_node("c", function(state, config) list()) |>
    add_edge(START, "a") |>
    add_edge("a", "b") |>
    add_edge("b", END)
  expect_error(g$add_edge("a", "c"), regexp = "already has a fixed")
})

test_that("compile() errors with no nodes", {
  schema <- workflow_state(x = list(default = 0L))
  g <- state_graph(schema)
  expect_error(g$compile(), regexp = "no nodes")
})

test_that("compile() errors with no START edge", {
  schema <- workflow_state(x = list(default = 0L))
  g <- state_graph(schema) |>
    add_node("a", function(state, config) list(x = 1L)) |>
    add_edge("a", END)
  expect_error(g$compile(), regexp = "exactly one edge")
})

test_that("compile() errors with no END path", {
  schema <- workflow_state(x = list(default = 0L))
  g <- state_graph(schema) |>
    add_node("a", function(state, config) list(x = 1L)) |>
    add_node("b", function(state, config) list(x = 2L)) |>
    add_edge(START, "a") |>
    add_edge("a", "b")
  expect_error(g$compile(), regexp = "at least one path|termination")
})

test_that("compile() errors when node has both fixed and conditional edge", {
  schema <- workflow_state(x = list(default = 0L))
  g <- state_graph(schema) |>
    add_node("a", function(state, config) list()) |>
    add_node("b", function(state, config) list()) |>
    add_node("c", function(state, config) list()) |>
    add_edge(START, "a") |>
    add_edge("a", "b")

  g$.__enclos_env__$private$.edges <- c(
    g$.__enclos_env__$private$.edges,
    list(list(from = "a", to = END))
  )
  g$.__enclos_env__$private$.conditional_edges <- list(
    list(
      from       = "a",
      routing_fn = function(state) "go",
      route_map  = list(go = "c")
    )
  )
  expect_error(g$compile(), regexp = "both a fixed edge and a conditional edge")
})

test_that("compiled graph runs and returns final state", {
  g <- make_simple_graph()
  runner <- g$compile()
  final <- runner$invoke()
  expect_equal(final$get("result"), "a_done")
})

test_that("conditional edges route correctly", {
  schema <- workflow_state(
    value  = list(default = 10L),
    result = list(default = "")
  )
  g <- state_graph(schema) |>
    add_node("check", function(state, config) list()) |>
    add_node("high",  function(state, config) list(result = "high")) |>
    add_node("low",   function(state, config) list(result = "low")) |>
    add_edge(START, "check") |>
    add_conditional_edge(
      "check",
      routing_fn = function(state) if (state$get("value") > 5L) "hi" else "lo",
      route_map  = list(hi = "high", lo = "low")
    ) |>
    add_edge("high", END) |>
    add_edge("low",  END)

  runner <- g$compile()

  final_high <- runner$invoke(list(value = 10L))
  expect_equal(final_high$get("result"), "high")

  final_low <- runner$invoke(list(value = 1L))
  expect_equal(final_low$get("result"), "low")
})

test_that("routing_fn returning unknown key errors loudly", {
  schema <- workflow_state(x = list(default = 0L))
  g <- state_graph(schema) |>
    add_node("a", function(state, config) list()) |>
    add_node("b", function(state, config) list()) |>
    add_edge(START, "a") |>
    add_conditional_edge("a", function(state) "NOPE", list(ok = "b")) |>
    add_edge("b", END)

  runner <- g$compile()
  expect_error(runner$invoke(), regexp = "unknown key")
})

test_that("pipe chaining works end to end", {
  schema <- workflow_state(n = list(default = 0L))
  runner <- state_graph(schema) |>
    add_node("inc", function(state, config) list(n = state$get("n") + 1L)) |>
    add_edge(START, "inc") |>
    add_edge("inc", END) |>
    compile()
  final <- runner$invoke(list(n = 5L))
  expect_equal(final$get("n"), 6L)
})

test_that("compile() is available as standalone function", {
  schema <- workflow_state(x = list(default = 0L))
  g <- state_graph(schema) |>
    add_node("n", function(state, config) list(x = 1L)) |>
    add_edge(START, "n") |>
    add_edge("n", END)
  runner <- compile(g)
  expect_true(inherits(runner, "GraphRunner"))
})
