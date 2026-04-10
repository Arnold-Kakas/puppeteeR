#' WorkflowState R6 class
#'
#' @description
#' Mutable shared state passed between graph nodes. Each named channel has a
#' default value and a reducer function that controls how updates are merged.
#'
#' @export
WorkflowState <- R6::R6Class(
  "WorkflowState",
  public = list(

    #' @description Create a new WorkflowState.
    #' @param schema Named list where each element is
    #'   `list(default = <value>, reducer = <function>)`. If `reducer` is
    #'   omitted, [reducer_last_n()] with a window of 20 is used for list
    #'   channels and [reducer_overwrite()] for all other channels.
    #' @returns A new `WorkflowState` object.
    initialize = function(schema) {
      rlang::check_required(schema)
      if (!is.list(schema) || length(schema) == 0L) {
        cli::cli_abort("{.arg schema} must be a non-empty named list.")
      }
      if (is.null(names(schema)) || any(names(schema) == "")) {
        cli::cli_abort("All channels in {.arg schema} must be named.")
      }

      private$.schema <- schema
      private$.reducers <- list()
      private$.data <- list()

      for (ch in names(schema)) {
        spec <- schema[[ch]]
        if (!is.list(spec) || !"default" %in% names(spec)) {
          cli::cli_abort(
            "Channel {.val {ch}} must be a list with at least a {.field default} element."
          )
        }
        reducer <- if (!is.null(spec$reducer)) {
          spec$reducer
        } else if (is.list(spec$default)) {
          reducer_last_n(20L)
        } else {
          reducer_overwrite()
        }
        if (!is.function(reducer)) {
          cli::cli_abort("Channel {.val {ch}}: {.field reducer} must be a function.")
        }
        private$.reducers[[ch]] <- reducer
        private$.data[ch] <- list(spec$default)
      }
    },

    #' @description Get the current value of a channel.
    #' @param key Character. Channel name.
    #' @returns The current channel value.
    get = function(key) {
      if (!key %in% names(private$.data)) {
        cli::cli_abort("Channel {.val {key}} is not in the workflow state schema.")
      }
      private$.data[[key]]
    },

    #' @description Set (apply reducer to) a single channel.
    #' @param key Character. Channel name.
    #' @param value New value passed to the reducer.
    #' @returns Invisibly, `self`.
    set = function(key, value) {
      if (!key %in% names(private$.data)) {
        cli::cli_abort("Channel {.val {key}} is not in the workflow state schema.")
      }
      old <- private$.data[[key]]
      private$.data[key] <- list(private$.reducers[[key]](old, value))
      invisible(self)
    },

    #' @description Apply a named list of updates to the state.
    #' @param updates Named list. Keys starting with `"."` are reserved and
    #'   silently ignored. Unknown keys raise an error (typo protection).
    #' @returns Invisibly, `self`.
    update = function(updates) {
      if (!is.list(updates)) {
        cli::cli_abort("{.arg updates} must be a named list.")
      }
      if (length(updates) == 0L) return(invisible(self))

      keys <- names(updates)
      if (is.null(keys)) {
        cli::cli_abort("{.arg updates} must be a named list.")
      }

      unknown <- setdiff(keys[!startsWith(keys, ".")], names(private$.data))
      if (length(unknown) > 0L) {
        cli::cli_abort(c(
          "Unknown channel(s) in update: {.val {unknown}}.",
          "i" = "Available channels: {.val {names(private$.data)}}."
        ))
      }

      for (k in keys) {
        if (!startsWith(k, ".")) self$set(k, updates[[k]])
      }
      invisible(self)
    },

    #' @description Return a deep copy of the current state as a plain list.
    #' @returns Named list.
    snapshot = function() {
      lapply(private$.data, identity)
    },

    #' @description Restore state from a snapshot.
    #' @param snap Named list previously produced by `$snapshot()`.
    #' @returns Invisibly, `self`.
    restore = function(snap) {
      unknown <- setdiff(names(snap), names(private$.data))
      if (length(unknown) > 0L) {
        cli::cli_abort("Snapshot contains unknown channel(s): {.val {unknown}}.")
      }
      for (k in names(snap)) {
        private$.data[k] <- list(snap[[k]])
      }
      invisible(self)
    },

    #' @description Return the names of all channels.
    #' @returns Character vector.
    keys = function() {
      names(private$.data)
    },

    #' @description Print a summary of the state.
    #' @param ... Ignored.
    print = function(...) {
      cli::cli_inform("WorkflowState with {length(private$.data)} channel(s):")
      for (k in names(private$.data)) {
        val <- private$.data[[k]]
        preview <- tryCatch(
          paste(utils::capture.output(utils::str(val, max.level = 1L)), collapse = " "),
          error = function(e) "<unprintable>"
        )
        if (nchar(preview) > 80L) preview <- paste0(substr(preview, 1L, 77L), "...")
        cli::cli_inform("  {.field {k}}: {preview}")
      }
      invisible(self)
    }
  ),

  active = list(
    #' @field schema The raw schema list (read-only). Used by [GraphRunner] to
    #'   reconstruct a fresh state on each `$invoke()` call.
    schema = function() private$.schema
  ),

  private = list(
    .data = list(),
    .reducers = list(),
    .schema = list()
  )
)

#' Create a WorkflowState
#'
#' @description
#' Constructs a [WorkflowState] from named channel specifications.
#'
#' @param ... Named arguments, each a `list(default = <value>)` optionally with
#'   a `reducer` element. If `reducer` is absent, [reducer_last_n()] with a
#'   window of 20 is used for list channels and [reducer_overwrite()] for all
#'   other channels.
#' @returns A [WorkflowState] object.
#' @export
#' @examples
#' ws <- workflow_state(
#'   messages = list(default = list(), reducer = reducer_append()),
#'   status   = list(default = "pending")
#' )
#' ws$get("status")
workflow_state <- function(...) {
  schema <- list(...)
  WorkflowState$new(schema)
}

#' Reducer: overwrite channel with new value
#'
#' The default reducer. Every update replaces the old value entirely.
#'
#' @returns A two-argument function `function(old, new)` that returns `new`.
#' @export
#' @examples
#' r <- reducer_overwrite()
#' r("old", "new")
reducer_overwrite <- function() {
  function(old, new) new  # nolint: object_usage_linter
}

#' Reducer: append new value to a list
#'
#' Wraps `new` in a `list()` and concatenates it to `old`. Useful for
#' accumulating messages.
#'
#' @returns A two-argument function `function(old, new)`.
#' @export
#' @examples
#' r <- reducer_append()
#' r(list("a"), "b")
reducer_append <- function() {
  function(old, new) c(old, list(new))
}

#' Reducer: merge lists with `modifyList`
#'
#' Performs a shallow merge of `new` into `old` using [modifyList()].
#' Useful for nested configuration state.
#'
#' @returns A two-argument function `function(old, new)`.
#' @export
#' @examples
#' r <- reducer_merge()
#' r(list(a = 1, b = 2), list(b = 99, c = 3))
reducer_merge <- function() {
  function(old, new) modifyList(old, new)
}

#' Reducer: keep only the last `n` entries
#'
#' Appends `new` to `old` then trims the list to at most `n` entries by
#' dropping the oldest. Use this instead of [reducer_append()] whenever the
#' channel feeds into an LLM call, to prevent the context window from growing
#' unboundedly and causing connection errors on long workflows.
#'
#' @param n Positive integer. Maximum number of entries to retain.
#' @returns A two-argument function `function(old, new)`.
#' @export
#' @examples
#' r <- reducer_last_n(3L)
#' r(list("a", "b", "c"), "d")   # drops "a", keeps "b", "c", "d"
reducer_last_n <- function(n) {
  if (!is.numeric(n) || length(n) != 1L || n < 1L) {
    cli::cli_abort("{.arg n} must be a positive integer.")
  }
  n <- as.integer(n)
  function(old, new) {
    updated <- c(old, list(new))
    if (length(updated) > n) updated <- tail(updated, n)
    updated
  }
}
