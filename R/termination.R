#' Termination condition: maximum iterations
#'
#' Stops execution when the iteration counter reaches `n`.
#'
#' @param n Integer. Maximum number of node executions.
#' @returns A `termination_condition` S3 object.
#' @export
#' @examples
#' cond <- max_turns(10L)
#' check_termination(cond, NULL, 10L, 0)
max_turns <- function(n) {
  if (!is.numeric(n) || length(n) != 1L || n < 1L) {
    cli::cli_abort("{.arg n} must be a positive integer.")
  }
  structure(list(n = as.integer(n)), class = c("max_turns", "termination_condition"))
}

#' Termination condition: cost limit
#'
#' Stops execution when the cumulative cost exceeds `dollars`.
#'
#' @param dollars Numeric. Cost threshold in USD.
#' @returns A `termination_condition` S3 object.
#' @export
#' @examples
#' cond <- cost_limit(1.00)
cost_limit <- function(dollars) {
  if (!is.numeric(dollars) || length(dollars) != 1L || dollars <= 0) {
    cli::cli_abort("{.arg dollars} must be a positive number.")
  }
  structure(
    list(dollars = dollars),
    class = c("cost_limit", "termination_condition")
  )
}

#' Termination condition: text pattern match
#'
#' Stops execution when the specified state channel contains a string matching
#' `pattern`.
#'
#' @param pattern Character. Passed to [base::grepl()].
#' @param channel Character. Name of the state channel to inspect.
#' @returns A `termination_condition` S3 object.
#' @export
#' @examples
#' cond <- text_match("DONE", channel = "status")
text_match <- function(pattern, channel = "messages") {
  if (!is.character(pattern) || length(pattern) != 1L) {
    cli::cli_abort("{.arg pattern} must be a length-1 character string.")
  }
  structure(
    list(pattern = pattern, channel = channel),
    class = c("text_match", "termination_condition")
  )
}

#' Termination condition: custom function
#'
#' Stops execution when `fn(state)` returns `TRUE`.
#'
#' @param fn Function `function(state)` returning a scalar logical.
#' @returns A `termination_condition` S3 object.
#' @export
#' @examples
#' cond <- custom_condition(function(state) state$get("done") == TRUE)
custom_condition <- function(fn) {
  check_is_function(fn)
  structure(list(fn = fn), class = c("custom_condition", "termination_condition"))
}

#' Evaluate a termination condition
#'
#' S3 generic called by [GraphRunner] after each node execution. Implement
#' this method to create custom termination condition classes.
#'
#' @param condition A `termination_condition` object.
#' @param state A [WorkflowState] object.
#' @param iteration Integer. Current iteration count.
#' @param total_cost Numeric. Cumulative cost so far.
#' @returns Logical scalar; `TRUE` means stop.
#' @export
check_termination <- function(condition, state, iteration, total_cost) {
  UseMethod("check_termination")
}

#' @export
check_termination.max_turns <- function(condition, state, iteration, total_cost) {
  iteration >= condition$n
}

#' @export
check_termination.cost_limit <- function(condition, state, iteration, total_cost) {
  total_cost >= condition$dollars
}

#' @export
check_termination.text_match <- function(condition, state, iteration, total_cost) {
  value <- tryCatch(state$get(condition$channel), error = function(e) "")
  if (is.list(value)) value <- paste(unlist(value), collapse = " ")
  grepl(condition$pattern, value, fixed = TRUE)
}

#' @export
check_termination.custom_condition <- function(condition, state, iteration, total_cost) {
  isTRUE(condition$fn(state))
}

#' @export
check_termination.or_condition <- function(condition, state, iteration, total_cost) {
  check_termination(condition$a, state, iteration, total_cost) ||
    check_termination(condition$b, state, iteration, total_cost)
}

#' @export
check_termination.and_condition <- function(condition, state, iteration, total_cost) {
  check_termination(condition$a, state, iteration, total_cost) &&
    check_termination(condition$b, state, iteration, total_cost)
}

#' Compose termination conditions
#'
#' Combine two termination conditions with `|` (OR) or `&` (AND).
#'
#' @param a,b `termination_condition` objects.
#' @returns A composite `termination_condition` object.
#' @name compose_termination
#' @examples
#' cond <- max_turns(10L) | cost_limit(1.0)
#' cond2 <- max_turns(10L) & text_match("done", channel = "status")
NULL

#' @rdname compose_termination
#' @export
`|.termination_condition` <- function(a, b) {
  structure(list(a = a, b = b), class = c("or_condition", "termination_condition"))
}

#' @rdname compose_termination
#' @export
`&.termination_condition` <- function(a, b) {
  structure(list(a = a, b = b), class = c("and_condition", "termination_condition"))
}
