test_that("sequential_workflow() requires a named list", {
  ag <- make_mock_agent("a")
  expect_error(sequential_workflow(list(ag)), "must be named")
  expect_error(sequential_workflow(list()),   "non-empty")
})

test_that("sequential_workflow() executes agents in order", {
  a1 <- make_mock_agent("first",  responses = "from first")
  a2 <- make_mock_agent("second", responses = "from second")

  runner <- sequential_workflow(list(first = a1, second = a2))
  result <- runner$invoke(list(messages = list("start")))

  msgs <- result$get("messages")
  expect_equal(msgs[[length(msgs)]], "from second")
})

test_that("sequential_workflow() with single agent reaches END", {
  ag <- make_mock_agent("solo", responses = "solo reply")
  runner <- sequential_workflow(list(solo = ag))
  result <- runner$invoke(list(messages = list("go")))
  msgs <- result$get("messages")
  expect_equal(msgs[[length(msgs)]], "solo reply")
})

test_that("sequential_workflow() accepts custom state_schema", {
  schema <- workflow_state(
    messages = list(default = list(), reducer = reducer_append()),
    meta     = list(default = "")
  )
  ag     <- make_mock_agent("a", responses = "ok")
  runner <- sequential_workflow(list(a = ag), state_schema = schema)
  result <- runner$invoke(list(messages = list("hi"), meta = "test"))
  expect_equal(result$get("meta"), "test")
})

test_that("supervisor_workflow() requires named workers", {
  mgr <- make_mock_agent("mgr")
  ag  <- make_mock_agent("w")
  expect_error(supervisor_workflow(mgr, list(ag)), "named")
})

test_that("supervisor_workflow() routes to DONE when no worker matched", {
  mgr <- make_mock_agent("mgr", responses = "DONE")
  w   <- make_mock_agent("worker", responses = "worker reply")

  runner <- supervisor_workflow(
    manager  = mgr,
    workers  = list(worker = w),
    max_rounds = 3L
  )
  result <- runner$invoke(list(messages = list("hello")))
  expect_true(inherits(result, "WorkflowState"))
})

test_that("supervisor_workflow() delegates to worker when name appears in response", {
  responses <- c("worker", "DONE")
  idx       <- 0L
  mgr_chat  <- mock_chat(responses)
  class(mgr_chat) <- c("Chat", "R6")
  mgr <- agent("mgr", mgr_chat)
  w   <- make_mock_agent("worker", responses = "worker reply")

  runner <- supervisor_workflow(
    manager    = mgr,
    workers    = list(worker = w),
    max_rounds = 4L
  )
  result <- runner$invoke(list(messages = list("start")))
  msgs <- result$get("messages")
  expect_true(any(vapply(msgs, function(m) m == "worker reply", logical(1))))
})

test_that("debate_workflow() requires at least 2 agents", {
  ag <- make_mock_agent("a")
  expect_error(debate_workflow(list(a = ag)), "at least two")
})

test_that("debate_workflow() requires named agents", {
  a1 <- make_mock_agent("a")
  a2 <- make_mock_agent("b")
  expect_error(debate_workflow(list(a1, a2)), "named")
})

test_that("debate_workflow() runs for max_rounds turns", {
  a1 <- make_mock_agent("pro",  responses = "pro point")
  a2 <- make_mock_agent("con",  responses = "con point")

  runner <- debate_workflow(
    agents     = list(pro = a1, con = a2),
    max_rounds = 2L
  )
  result <- runner$invoke(list(messages = list("Is R great?")))
  msgs <- result$get("messages")
  expect_gte(length(msgs), 2L)
})

test_that("debate_workflow() with judge stops on 'done'", {
  a1    <- make_mock_agent("pro", responses = "pro point")
  a2    <- make_mock_agent("con", responses = "con point")
  judge <- make_mock_agent("judge", responses = "done")

  runner <- debate_workflow(
    agents     = list(pro = a1, con = a2),
    max_rounds = 5L,
    judge      = judge
  )
  result <- runner$invoke(list(messages = list("debate topic")))
  expect_true(inherits(result, "WorkflowState"))
})
