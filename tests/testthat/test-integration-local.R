# Integration tests using a local LLM (LM Studio or compatible server).
#
# Prerequisites:
#   1. LM Studio running with a model loaded.
#   2. The server listening at http://localhost:1234 (default).
#
# Override defaults via environment variables:
#   LOCAL_LLM_BASE_URL  - e.g. "http://localhost:1234/v1"
#   LOCAL_LLM_MODEL     - e.g. "qwen/qwen3.5-9b"
#
# All tests call skip_if_no_local_llm() and are skipped automatically when
# LM Studio is not running, so they never block CI.

test_that("local LLM returns a non-empty string from a simple prompt", {
  skip_if_no_local_llm()

  chat <- make_local_chat()
  ag   <- agent("local", chat)

  result <- ag$chat("Reply with only the word 'pong'.")
  expect_true(is.character(result))
  expect_true(nchar(trimws(result)) > 0L)
})

test_that("single-node graph completes with a local LLM", {
  skip_if_no_local_llm()

  schema <- workflow_state(
    question = list(default = ""),
    answer   = list(default = "")
  )

  chat <- make_local_chat()
  ag   <- agent("responder", chat)

  runner <- state_graph(schema) |>
    add_node("respond", function(state, config) {
      q   <- state$get("question")
      ans <- config$agents$responder$chat(
        paste0("Answer in one short sentence: ", q)
      )
      list(answer = as.character(ans))
    }) |>
    add_edge(START, "respond") |>
    add_edge("respond", END) |>
    compile(agents = list(responder = ag))

  final <- runner$invoke(list(question = "What is 2 + 2?"))
  answer <- final$get("answer")

  expect_true(is.character(answer))
  expect_true(nchar(trimws(answer)) > 0L)
})

test_that("two-node sequential graph accumulates messages with a local LLM", {
  skip_if_no_local_llm()

  a1 <- agent("drafter",  make_local_chat())
  a2 <- agent("reviewer", make_local_chat())

  runner <- sequential_workflow(list(drafter = a1, reviewer = a2))
  result <- runner$invoke(list(messages = list("Write one sentence about R.")))

  msgs <- result$get("messages")
  expect_gte(length(msgs), 2L)
  expect_true(all(vapply(msgs, function(m) nchar(as.character(m)) > 0L, logical(1))))
})

test_that("on_event fires node_start and node_end with a local LLM", {
  skip_if_no_local_llm()

  schema <- workflow_state(reply = list(default = ""))
  ag     <- agent("bot", make_local_chat())
  events <- character(0)

  runner <- state_graph(schema) |>
    add_node("chat", function(state, config) {
      r <- config$agents$bot$chat("Say 'hi' in one word.")
      list(reply = as.character(r))
    }) |>
    add_edge(START, "chat") |>
    add_edge("chat", END) |>
    compile(agents = list(bot = ag))

  runner$invoke(config = list(
    on_event = function(event) events <<- c(events, event$type)
  ))

  expect_equal(events, c("node_start", "node_end"))
})

test_that("retry_policy recovers when node fails once with a local LLM", {
  skip_if_no_local_llm()

  attempt_n <- 0L
  schema    <- workflow_state(reply = list(default = ""))
  ag        <- agent("bot", make_local_chat())

  runner <- state_graph(schema) |>
    add_node(
      "chat",
      function(state, config) {
        attempt_n <<- attempt_n + 1L
        if (attempt_n < 2L) stop("simulated transient error")
        r <- config$agents$bot$chat("Say 'ok' in one word.")
        list(reply = as.character(r))
      },
      retry = retry_policy(max_attempts = 3L, wait_seconds = 0)
    ) |>
    add_edge(START, "chat") |>
    add_edge("chat", END) |>
    compile(agents = list(bot = ag))

  final <- runner$invoke()
  expect_equal(attempt_n, 2L)
  expect_true(nchar(trimws(final$get("reply"))) > 0L)
})

test_that("checkpointer saves and restores state across invokes with a local LLM", {
  skip_if_no_local_llm()

  cp     <- memory_checkpointer()
  schema <- workflow_state(
    question = list(default = ""),
    answer   = list(default = "")
  )
  ag <- agent("bot", make_local_chat())

  runner <- state_graph(schema) |>
    add_node("respond", function(state, config) {
      r <- config$agents$bot$chat(
        paste0("One sentence: ", state$get("question"))
      )
      list(answer = as.character(r))
    }) |>
    add_edge(START, "respond") |>
    add_edge("respond", END) |>
    compile(agents = list(bot = ag), checkpointer = cp)

  runner$invoke(
    list(question = "What is R?"),
    config = list(thread_id = "t1")
  )

  saved <- runner$get_state("t1")
  expect_false(is.null(saved))
  expect_true(nchar(trimws(saved[["answer"]])) > 0L)
})
