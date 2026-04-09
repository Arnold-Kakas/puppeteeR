mock_chat <- function(responses = "mock response") {
  idx <- 0L
  responses <- as.list(responses)

  list(
    chat = function(...) {
      idx <<- idx + 1L
      resp <- responses[[min(idx, length(responses))]]
      resp
    },
    get_cost   = function(...) structure(0, class = c("ellmer_dollars", "numeric")),
    get_tokens = function(...) data.frame(role = character(0), tokens = numeric(0),
                                          tokens_total = numeric(0),
                                          stringsAsFactors = FALSE),
    get_turns  = function() list(),
    set_turns  = function(turns) invisible(NULL),
    get_system_prompt = function() "",
    set_system_prompt = function(p) invisible(NULL),
    register_tool     = function(t) invisible(NULL),
    clone = function(deep = FALSE) mock_chat(responses),
    class = "Chat"
  )
}

make_mock_agent <- function(name = "test_agent", responses = "mock response") {
  chat_obj <- mock_chat(responses)
  class(chat_obj) <- c("Chat", "R6")
  agent(name = name, chat = chat_obj)
}

skip_if_no_api_key <- function(var = "ANTHROPIC_API_KEY") {
  testthat::skip_if(
    nchar(Sys.getenv(var)) == 0L,
    message = paste("No", var, "found - skipping integration test.")
  )
}
