#' Checkpointer base class
#'
#' @description
#' Abstract interface for persisting workflow state. Concrete subclasses:
#' [MemoryCheckpointer], [RDSCheckpointer], [SQLiteCheckpointer].
#'
#' @export
Checkpointer <- R6::R6Class(
  "Checkpointer",
  public = list(

    #' @description Save a state snapshot.
    #' @param thread_id Character. Identifies the workflow run.
    #' @param step Integer. Current step number.
    #' @param state_snapshot Named list from `WorkflowState$snapshot()`.
    save = function(thread_id, step, state_snapshot) {
      cli::cli_abort("{.cls {class(self)[[1L]]}} must implement {.fn $save}.")
    },

    #' @description Load the most recent snapshot for a thread.
    #' @param thread_id Character.
    #' @returns `list(step = <int>, state = <list>)` or `NULL`.
    load_latest = function(thread_id) {
      cli::cli_abort("{.cls {class(self)[[1L]]}} must implement {.fn $load_latest}.")
    },

    #' @description Load a snapshot at an exact step.
    #' @param thread_id Character.
    #' @param step Integer.
    #' @returns State snapshot list or `NULL`.
    load_step = function(thread_id, step) {
      cli::cli_abort("{.cls {class(self)[[1L]]}} must implement {.fn $load_step}.")
    },

    #' @description List all thread IDs that have checkpoints.
    #' @returns Character vector.
    list_threads = function() {
      cli::cli_abort("{.cls {class(self)[[1L]]}} must implement {.fn $list_threads}.")
    }
  )
)

#' In-memory checkpointer
#'
#' @description
#' Stores checkpoints in a named list in RAM. State is lost when the R session
#' ends. Suitable for development, testing, and short workflows.
#'
#' @export
MemoryCheckpointer <- R6::R6Class(
  "MemoryCheckpointer",
  inherit = Checkpointer,
  public = list(

    #' @description Initialise an empty in-memory store.
    initialize = function() {
      private$.store <- list()
    },

    #' @description Save a snapshot.
    #' @param thread_id Character.
    #' @param step Integer.
    #' @param state_snapshot Named list.
    save = function(thread_id, step, state_snapshot) {
      if (is.null(private$.store[[thread_id]])) {
        private$.store[[thread_id]] <- list()
      }
      private$.store[[thread_id]][[as.character(step)]] <- state_snapshot
      invisible(NULL)
    },

    #' @description Load the latest snapshot.
    #' @param thread_id Character.
    #' @returns `list(step, state)` or `NULL`.
    load_latest = function(thread_id) {
      thread <- private$.store[[thread_id]]
      if (is.null(thread) || length(thread) == 0L) return(NULL)
      steps <- as.integer(names(thread))
      max_step <- max(steps)
      list(step = max_step, state = thread[[as.character(max_step)]])
    },

    #' @description Load snapshot at exact step.
    #' @param thread_id Character.
    #' @param step Integer.
    #' @returns State snapshot or `NULL`.
    load_step = function(thread_id, step) {
      private$.store[[thread_id]][[as.character(step)]]
    },

    #' @description Return all thread IDs.
    #' @returns Character vector.
    list_threads = function() {
      names(private$.store)
    }
  ),

  private = list(.store = NULL)
)

#' RDS file-based checkpointer
#'
#' @description
#' Persists each checkpoint as an `.rds` file under `{dir}/{thread_id}/step_{n}.rds`.
#'
#' @export
RDSCheckpointer <- R6::R6Class(
  "RDSCheckpointer",
  inherit = Checkpointer,
  public = list(

    #' @description Create an RDS checkpointer.
    #' @param dir Character. Directory path where checkpoints are written.
    initialize = function(dir) {
      rlang::check_required(dir)
      if (!dir.exists(dir)) dir.create(dir, recursive = TRUE)
      private$.dir <- dir
    },

    #' @description Save a snapshot as an RDS file.
    #' @param thread_id Character.
    #' @param step Integer.
    #' @param state_snapshot Named list.
    save = function(thread_id, step, state_snapshot) {
      thread_dir <- file.path(private$.dir, thread_id)
      if (!dir.exists(thread_dir)) dir.create(thread_dir, recursive = TRUE)
      path <- file.path(thread_dir, paste0("step_", step, ".rds"))
      saveRDS(state_snapshot, path)
      invisible(NULL)
    },

    #' @description Load the latest snapshot.
    #' @param thread_id Character.
    #' @returns `list(step, state)` or `NULL`.
    load_latest = function(thread_id) {
      thread_dir <- file.path(private$.dir, thread_id)
      if (!dir.exists(thread_dir)) return(NULL)
      files <- list.files(thread_dir, pattern = "^step_\\d+\\.rds$", full.names = TRUE)
      if (length(files) == 0L) return(NULL)
      steps <- as.integer(gsub("[^0-9]", "", basename(files)))
      max_step <- max(steps)
      best <- files[which.max(steps)]
      list(step = max_step, state = readRDS(best))
    },

    #' @description Load snapshot at exact step.
    #' @param thread_id Character.
    #' @param step Integer.
    #' @returns State snapshot or `NULL`.
    load_step = function(thread_id, step) {
      path <- file.path(private$.dir, thread_id, paste0("step_", step, ".rds"))
      if (!file.exists(path)) return(NULL)
      readRDS(path)
    },

    #' @description Return all thread IDs.
    #' @returns Character vector.
    list_threads = function() {
      dirs <- list.dirs(private$.dir, full.names = FALSE, recursive = FALSE)
      dirs[nchar(dirs) > 0L]
    }
  ),

  private = list(.dir = NULL)
)

#' SQLite-based checkpointer
#'
#' @description
#' Persists checkpoints in a SQLite database. Requires the `DBI` and `RSQLite`
#' packages.
#'
#' @export
SQLiteCheckpointer <- R6::R6Class(
  "SQLiteCheckpointer",
  inherit = Checkpointer,
  public = list(

    #' @description Create a SQLite checkpointer.
    #' @param path Character. Path to the SQLite database file.
    initialize = function(path) {
      rlang::check_required(path)
      rlang::check_installed("DBI", reason = "for SQLiteCheckpointer")
      rlang::check_installed("RSQLite", reason = "for SQLiteCheckpointer")
      private$.path <- path
      con <- DBI::dbConnect(RSQLite::SQLite(), path)
      on.exit(DBI::dbDisconnect(con), add = TRUE)
      DBI::dbExecute(con,
        "CREATE TABLE IF NOT EXISTS checkpoints (
           thread_id  TEXT    NOT NULL,
           step       INTEGER NOT NULL,
           state      BLOB    NOT NULL,
           created_at TEXT    NOT NULL,
           PRIMARY KEY (thread_id, step)
         )"
      )
    },

    #' @description Save a snapshot.
    #' @param thread_id Character.
    #' @param step Integer.
    #' @param state_snapshot Named list.
    save = function(thread_id, step, state_snapshot) {
      con <- DBI::dbConnect(RSQLite::SQLite(), private$.path)
      on.exit(DBI::dbDisconnect(con), add = TRUE)
      blob <- list(serialize(state_snapshot, connection = NULL))
      DBI::dbExecute(
        con,
        "INSERT OR REPLACE INTO checkpoints (thread_id, step, state, created_at)
         VALUES (?, ?, ?, ?)",
        list(thread_id, as.integer(step), blob, format(Sys.time()))
      )
      invisible(NULL)
    },

    #' @description Load the latest snapshot.
    #' @param thread_id Character.
    #' @returns `list(step, state)` or `NULL`.
    load_latest = function(thread_id) {
      con <- DBI::dbConnect(RSQLite::SQLite(), private$.path)
      on.exit(DBI::dbDisconnect(con), add = TRUE)
      row <- DBI::dbGetQuery(
        con,
        "SELECT step, state FROM checkpoints
          WHERE thread_id = ?
          ORDER BY step DESC
          LIMIT 1",
        list(thread_id)
      )
      if (nrow(row) == 0L) return(NULL)
      list(
        step  = row$step[[1L]],
        state = unserialize(row$state[[1L]])
      )
    },

    #' @description Load snapshot at exact step.
    #' @param thread_id Character.
    #' @param step Integer.
    #' @returns State snapshot or `NULL`.
    load_step = function(thread_id, step) {
      con <- DBI::dbConnect(RSQLite::SQLite(), private$.path)
      on.exit(DBI::dbDisconnect(con), add = TRUE)
      row <- DBI::dbGetQuery(
        con,
        "SELECT state FROM checkpoints WHERE thread_id = ? AND step = ?",
        list(thread_id, as.integer(step))
      )
      if (nrow(row) == 0L) return(NULL)
      unserialize(row$state[[1L]])
    },

    #' @description Return all thread IDs.
    #' @returns Character vector.
    list_threads = function() {
      con <- DBI::dbConnect(RSQLite::SQLite(), private$.path)
      on.exit(DBI::dbDisconnect(con), add = TRUE)
      DBI::dbGetQuery(
        con, "SELECT DISTINCT thread_id FROM checkpoints ORDER BY thread_id"
      )$thread_id
    }
  ),

  private = list(.path = NULL)
)

#' Create an in-memory checkpointer
#'
#' @returns A [MemoryCheckpointer] object.
#' @export
#' @examples
#' cp <- memory_checkpointer()
memory_checkpointer <- function() MemoryCheckpointer$new()

#' Create an RDS file checkpointer
#'
#' @param dir Character. Directory to store `.rds` files.
#' @returns An [RDSCheckpointer] object.
#' @export
#' @examples
#' \dontrun{
#' cp <- rds_checkpointer(tempdir())
#' }
rds_checkpointer <- function(dir) RDSCheckpointer$new(dir)

#' Create a SQLite checkpointer
#'
#' @param path Character. Path to the SQLite database file.
#' @returns A [SQLiteCheckpointer] object.
#' @export
#' @examples
#' \dontrun{
#' cp <- sqlite_checkpointer(tempfile(fileext = ".sqlite"))
#' }
sqlite_checkpointer <- function(path) SQLiteCheckpointer$new(path)
