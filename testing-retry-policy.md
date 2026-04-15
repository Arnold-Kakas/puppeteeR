# Testing: Node Retry Policies

Manual testing checklist for the `retry_policy` feature
(`node-retry-policy` branch).

------------------------------------------------------------------------

## 1. Load the package

``` r
devtools::load_all()
```

------------------------------------------------------------------------

## 2. Run the unit tests

``` r
testthat::test_file("tests/testthat/test-runner.R")
```

All 11 tests should pass (6 pre-existing + 5 new retry tests).

------------------------------------------------------------------------

## 3. Smoke-test: successful retry after transient failures

Simulates a node that fails twice then succeeds on the third attempt.

``` r
devtools::load_all()

attempt_n <- 0L
flaky_fn <- function(state, config) {
  attempt_n <<- attempt_n + 1L
  message("Attempt: ", attempt_n)
  if (attempt_n < 3L) stop("transient error")
  list(result = "recovered")
}

schema <- workflow_state(result = list(default = ""))
runner <- state_graph(schema) |>
  add_node("flaky", flaky_fn, retry = retry_policy(max_attempts = 3L, wait_seconds = 0)) |>
  add_edge(START, "flaky") |>
  add_edge("flaky", END) |>
  compile()

final <- runner$invoke()
final$get("result")   # expected: "recovered"
attempt_n             # expected: 3
```

------------------------------------------------------------------------

## 4. Smoke-test: exhausted retries throw with attempt count in message

``` r
always_fail <- function(state, config) stop("permanent failure")

schema <- workflow_state(x = list(default = 0L))
runner <- state_graph(schema) |>
  add_node("bad", always_fail, retry = retry_policy(max_attempts = 3L, wait_seconds = 0)) |>
  add_edge(START, "bad") |>
  add_edge("bad", END) |>
  compile()

tryCatch(
  runner$invoke(),
  error = function(e) message(conditionMessage(e))
)
# expected message contains: "3 attempt(s)" and "permanent failure"
```

------------------------------------------------------------------------

## 5. Smoke-test: exponential backoff (visual timing check)

``` r
attempt_n <- 0L
flaky_fn <- function(state, config) {
  attempt_n <<- attempt_n + 1L
  message(Sys.time(), " — attempt ", attempt_n)
  if (attempt_n < 3L) stop("fail")
  list(result = "ok")
}

schema <- workflow_state(result = list(default = ""))
runner <- state_graph(schema) |>
  add_node("n", flaky_fn,
           retry = retry_policy(max_attempts = 3L, wait_seconds = 1, backoff = 2)) |>
  add_edge(START, "n") |>
  add_edge("n", END) |>
  compile()

runner$invoke()
# expected: ~1s gap between attempt 1 and 2, ~2s gap between attempt 2 and 3
```

------------------------------------------------------------------------

## 6. Smoke-test: node without retry still reports node name on error

``` r
schema <- workflow_state(x = list(default = 0L))
runner <- state_graph(schema) |>
  add_node("exploder", function(state, config) stop("kaboom")) |>
  add_edge(START, "exploder") |>
  add_edge("exploder", END) |>
  compile()

tryCatch(
  runner$invoke(),
  error = function(e) message(conditionMessage(e))
)
# expected message contains: "exploder" and "kaboom"
```

------------------------------------------------------------------------

## 7. Validation: bad retry_policy arguments are rejected

``` r
retry_policy(max_attempts = 1L)   # error: max_attempts must be >= 2
retry_policy(wait_seconds = -1)   # error: wait_seconds must be non-negative
retry_policy(backoff = 0)         # error: backoff must be positive
```

------------------------------------------------------------------------

## 8. Validation: non-retry_policy object rejected by add_node()

``` r
schema <- workflow_state(x = list(default = 0L))
g <- state_graph(schema)
g$add_node("n", function(state, config) list(), retry = list(max_attempts = 3L))
# error: retry must be a <retry_policy> object or NULL
```

------------------------------------------------------------------------

## 9. Full test suite

Confirm no regressions across the whole package:

``` r
devtools::test()
```

------------------------------------------------------------------------

## 10. Documentation check

``` r
devtools::document()
?retry_policy   # should show roxygen2 docs with @param, @returns, @examples
```
