test_that("build_cost_report returns empty frame for no agents", {
  report <- build_cost_report(list())
  expect_s3_class(report, "data.frame")
  expect_equal(nrow(report), 0L)
  expect_named(report, c("agent", "input_tokens", "output_tokens", "cost"))
})

test_that("build_cost_report includes TOTAL row", {
  ag1 <- make_mock_agent("a1")
  ag2 <- make_mock_agent("a2")
  report <- build_cost_report(list(a1 = ag1, a2 = ag2))
  expect_true("TOTAL" %in% report$agent)
})

test_that("build_cost_report sums correctly", {
  ag1 <- make_mock_agent("a1")
  ag2 <- make_mock_agent("a2")
  report <- build_cost_report(list(a1 = ag1, a2 = ag2))
  total_row <- report[report$agent == "TOTAL", ]
  non_total  <- report[report$agent != "TOTAL", ]
  expect_equal(total_row$cost, sum(non_total$cost))
  expect_equal(total_row$input_tokens, sum(non_total$input_tokens))
})
