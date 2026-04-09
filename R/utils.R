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
