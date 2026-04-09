#' Agent R6 class
#'
#' @description
#' A thin, opinionated wrapper around an `ellmer::Chat` object. Adds identity
#' (name, role), conversation management helpers, and cumulative cost tracking.
#' All LLM logic is delegated to `ellmer`.
#'
#' @name Agent
#' @aliases Agent
#' @export
Agent <- R6::R6Class(
  "Agent",
  public = list(

    #' @description Create a new Agent.
    #' @param name Character. Unique identifier used in graph node configs.
    #' @param chat An `ellmer::Chat` object (e.g. from `ellmer::chat_anthropic()`).
    #' @param role Character or `NULL`. Short role description prepended to the
    #'   system prompt.
    #' @param instructions Character or `NULL`. Detailed instructions appended to
    #'   the system prompt.
    #' @param tools List of `ellmer::tool()` objects to register on the chat.
    #' @param handoffs Character vector of agent names this agent may hand off to.
    #' @param max_retries Integer. Number of times to retry a failed API call
    #'   before raising an error (default `3L`). Set to `0L` to disable retries.
    #' @param retry_wait Numeric. Seconds to wait between retries (default `5`).
    #' @returns A new `Agent` object.
    initialize = function(name, chat, role = NULL, instructions = NULL,
                          tools = list(), handoffs = character(),
                          max_retries = 3L, retry_wait = 5) {
      rlang::check_required(name)
      rlang::check_required(chat)
      rlang::check_installed("ellmer", reason = "to create Agent objects")
      if (!is.character(name) || length(name) != 1L) {
        cli::cli_abort("{.arg name} must be a length-1 character string.")
      }
      if (!inherits(chat, "Chat")) {
        cli::cli_abort("{.arg chat} must be an {.cls Chat} object from {.pkg ellmer}.")
      }
      private$.name        <- name
      private$.chat        <- chat
      private$.role        <- role
      private$.instructions <- instructions
      private$.handoffs    <- handoffs
      private$.max_retries <- as.integer(max_retries)
      private$.retry_wait  <- as.numeric(retry_wait)

      system_parts <- character(0)
      if (!is.null(role)) system_parts <- c(system_parts, paste0("Role: ", role))
      if (!is.null(instructions)) system_parts <- c(system_parts, instructions)
      if (length(system_parts) > 0L) {
        existing <- private$.chat$get_system_prompt()
        combined <- if (is.null(existing) || nchar(existing) == 0L) {
          paste(system_parts, collapse = "\n\n")
        } else {
          paste(c(existing, paste(system_parts, collapse = "\n\n")), collapse = "\n\n")
        }
        private$.chat$set_system_prompt(combined)
      }

      if (length(tools) > 0L) {
        for (t in tools) {
          private$.chat$register_tool(t)
        }
      }
    },

    #' @description Send a message to the agent, retrying on transient errors.
    #' @param ... Passed to `ellmer::Chat$chat()`.
    #' @returns The assistant's response as a character string.
    chat = function(...) {
      result <- private$.with_retry(function() private$.chat$chat(...))
      private$.track_cost()
      result
    },

    #' @description Send a message and receive a structured response.
    #' @param ... Passed to `ellmer::Chat$chat_structured()`.
    #' @param type An `ellmer` type specification for the structured output.
    #' @returns Parsed R object matching `type`.
    chat_structured = function(..., type) {
      result <- private$.with_retry(function() private$.chat$chat_structured(..., type = type))
      private$.track_cost()
      result
    },

    #' @description Stream a response from the agent.
    #' @param ... Passed to `ellmer::Chat$stream()`.
    #' @returns A `coro` generator yielding text chunks.
    stream = function(...) {
      private$.chat$stream(...)
    },

    #' @description Create a fresh copy of this agent with empty conversation history.
    #' @returns A new `Agent` with the same configuration but no turns.
    clone_fresh = function() {
      new_chat <- private$.chat$clone(deep = TRUE)
      new_chat$set_turns(list())
      Agent$new(
        name = private$.name,
        chat = new_chat,
        handoffs = private$.handoffs
      )
    },

    #' @description Return the current conversation turns.
    #' @returns List of turn objects from `ellmer`.
    get_turns = function() {
      private$.chat$get_turns()
    },

    #' @description Replace the conversation turns.
    #' @param turns List of turn objects.
    set_turns = function(turns) {
      private$.chat$set_turns(turns)
      invisible(self)
    },

    #' @description Return cumulative cost for this agent.
    #' @returns Numeric, total USD spent so far.
    get_cost = function() {
      private$.cumulative_cost
    },

    #' @description Return cumulative token counts.
    #' @returns Named list with `input` and `output` integer elements.
    get_tokens = function() {
      private$.cumulative_tokens
    },

    #' @description Print a summary of the agent.
    #' @param ... Ignored.
    print = function(...) {
      cli::cli_inform(c(
        "!" = "Agent: {.strong {private$.name}}",
        " " = "Role: {private$.role %||% '(none)'}",
        " " = "Cost: ${format(private$.cumulative_cost, digits = 4)}",
        " " = "Tokens: {private$.cumulative_tokens$input} in / {private$.cumulative_tokens$output} out"
      ))
      invisible(self)
    }
  ),

  active = list(
    #' @field name Agent name (read-only).
    name = function() private$.name,

    #' @field role Agent role description (read-only).
    role = function() private$.role,

    #' @field handoffs Names of agents this agent may hand off to (read-only).
    handoffs = function() private$.handoffs
  ),

  private = list(
    .name = NULL,
    .chat = NULL,
    .role = NULL,
    .instructions = NULL,
    .handoffs = NULL,
    .max_retries = 3L,
    .retry_wait  = 5,
    .cumulative_cost = 0,
    .cumulative_tokens = list(input = 0L, output = 0L),

    .with_retry = function(fn) {
      attempts <- max(1L, private$.max_retries + 1L)
      for (i in seq_len(attempts)) {
        result <- tryCatch(fn(), error = function(e) e)
        if (!inherits(result, "error")) return(result)
        if (i == attempts) cli::cli_abort(conditionMessage(result), parent = result)
        cli::cli_warn(c(
          "!" = "Agent {.val {private$.name}}: API error on attempt {i}/{attempts}.",
          "i" = "{conditionMessage(result)}",
          "i" = "Retrying in {private$.retry_wait}s..."
        ))
        Sys.sleep(private$.retry_wait)
      }
    },

    .track_cost = function() {
      tryCatch({
        private$.cumulative_cost <- as.numeric(private$.chat$get_cost())
        tokens_df <- private$.chat$get_tokens()
        if (!is.null(tokens_df) && nrow(tokens_df) > 0L) {
          private$.cumulative_tokens$input  <-
            sum(tokens_df$tokens[tokens_df$role == "user"],     na.rm = TRUE)
          private$.cumulative_tokens$output <-
            sum(tokens_df$tokens[tokens_df$role == "assistant"], na.rm = TRUE)
        }
      }, error = function(e) NULL)
    }
  )
)

#' @describeIn Agent Construct an `Agent` from an `ellmer::Chat` object.
#' @param name Character. Unique identifier for this agent within a workflow.
#' @param chat An `ellmer::Chat` object (e.g. `ellmer::chat_anthropic()`).
#' @param role Character or `NULL`. Short role description.
#' @param instructions Character or `NULL`. Detailed system instructions.
#' @param tools List of `ellmer::tool()` objects.
#' @param handoffs Character vector of agent names for handoffs.
#' @param max_retries Integer. Retries on transient API errors (default `3L`).
#' @param retry_wait Numeric. Seconds between retries (default `5`).
#' @returns An `Agent` R6 object.
#' @export
#' @examples
#' \dontrun{
#' ag <- agent(
#'   name        = "researcher",
#'   chat        = ellmer::chat_anthropic(),
#'   role        = "Senior researcher",
#'   instructions = "Be thorough and cite sources.",
#'   max_retries = 3L,
#'   retry_wait  = 5
#' )
#' }
agent <- function(name, chat, role = NULL, instructions = NULL,
                  tools = list(), handoffs = character(),
                  max_retries = 3L, retry_wait = 5) {
  Agent$new(
    name = name, chat = chat, role = role,
    instructions = instructions, tools = tools, handoffs = handoffs,
    max_retries = max_retries, retry_wait = retry_wait
  )
}

`%||%` <- function(x, y) if (is.null(x)) y else x
