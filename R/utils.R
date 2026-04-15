#' Define a retry policy for a graph node
#'
#' Passed to [add_node()] via the `retry` argument. When a node function throws
#' an error, the runner waits `wait_seconds` and retries up to `max_attempts`
#' times before re-throwing.
#'
#' @param max_attempts Positive integer. Total number of attempts (including the
#'   first). Must be >= 2.
#' @param wait_seconds Non-negative number. Seconds to wait between attempts.
#'   Each subsequent wait is multiplied by `backoff` (default 1 = no backoff).
#' @param backoff Positive number. Multiplier applied to `wait_seconds` after
#'   each failed attempt. Use `2` for exponential backoff.
#' @returns An S3 object of class `retry_policy`.
#' @export
#' @examples
#' rp <- retry_policy(max_attempts = 3L, wait_seconds = 1L, backoff = 2)
retry_policy <- function(max_attempts = 3L, wait_seconds = 1L, backoff = 1) {
  if (!is.numeric(max_attempts) || length(max_attempts) != 1L || max_attempts < 2L) {
    cli::cli_abort("{.arg max_attempts} must be an integer >= 2.")
  }
  if (!is.numeric(wait_seconds) || length(wait_seconds) != 1L || wait_seconds < 0) {
    cli::cli_abort("{.arg wait_seconds} must be a non-negative number.")
  }
  if (!is.numeric(backoff) || length(backoff) != 1L || backoff <= 0) {
    cli::cli_abort("{.arg backoff} must be a positive number.")
  }
  structure(
    list(
      max_attempts = as.integer(max_attempts),
      wait_seconds = wait_seconds,
      backoff      = backoff
    ),
    class = "retry_policy"
  )
}

check_is_retry_policy <- function(x, arg = "retry") {
  if (!is.null(x) && !inherits(x, "retry_policy")) {
    cli::cli_abort(
      "{.arg {arg}} must be a {.cls retry_policy} object or {.val NULL}, \\
       not {.obj_type_friendly {x}}."
    )
  }
  invisible(NULL)
}

is_sentinel <- function(x) {
  inherits(x, "puppeteer_sentinel")
}

sentinel_id <- function(x) {
  if (is_sentinel(x)) as.character(x) else x
}

check_node_name <- function(name, nodes, allow_sentinel = TRUE) {
  if (allow_sentinel && is_sentinel(name)) return(invisible(NULL))
  if (!is.character(name) || length(name) != 1L || is.na(name) || nchar(name) == 0L) {
    cli::cli_abort("Node name must be a non-empty string, not {.obj_type_friendly {name}}.")
  }
  if (!is.null(nodes) && !name %in% names(nodes)) {
    cli::cli_abort("Node {.val {name}} is not registered in the graph.")
  }
  invisible(NULL)
}

check_is_function <- function(fn, arg = "fn") {
  if (!is.function(fn)) {
    cli::cli_abort("{.arg {arg}} must be a function, not {.obj_type_friendly {fn}}.")
  }
  invisible(NULL)
}

check_named_list <- function(x, arg = "x") {
  if (!is.list(x) || is.null(names(x)) || any(names(x) == "")) {
    cli::cli_abort("{.arg {arg}} must be a fully named list.")
  }
  invisible(NULL)
}
