make_test_graph <- function() {
  schema <- workflow_state(result = list(default = NULL))
  state_graph(schema) |>
    add_node("classify", function(state, config) list()) |>
    add_node("respond",  function(state, config) list()) |>
    add_edge(START, "classify") |>
    add_conditional_edge(
      "classify",
      routing_fn = function(state) "respond",
      route_map  = list(respond = "respond", done = END)
    ) |>
    add_edge("respond", END)
}

test_that("as_dot() returns a non-empty string", {
  g <- make_test_graph()
  dot <- g$as_dot()
  expect_type(dot, "character")
  expect_gt(nchar(dot), 0L)
  expect_true(grepl("digraph", dot))
})

test_that("as_dot() contains node names", {
  g <- make_test_graph()
  dot <- g$as_dot()
  expect_true(grepl("classify", dot))
  expect_true(grepl("respond", dot))
  expect_true(grepl("START", dot))
  expect_true(grepl("END", dot))
})

test_that("as_dot() marks conditional edges as dashed", {
  g <- make_test_graph()
  dot <- g$as_dot()
  expect_true(grepl("dashed", dot))
})

test_that("as_mermaid() returns valid mermaid string", {
  g <- make_test_graph()
  mmd <- g$as_mermaid()
  expect_type(mmd, "character")
  expect_true(grepl("graph TD", mmd))
})

test_that("as_dot() snapshot is stable", {
  g <- make_test_graph()
  dot <- g$as_dot()
  expect_snapshot(dot)
})
