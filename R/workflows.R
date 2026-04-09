#' Build a sequential workflow
#'
#' Creates a linear chain where each agent receives the last message and appends
#' its response: `agent1 -> agent2 -> ... -> END`.
#'
#' @param agents Named list of `Agent` objects, executed in order.
#' @param state_schema A [WorkflowState] or `NULL` (uses default
#'   `messages` + `reducer_append()`).
#' @returns A compiled [GraphRunner].
#' @export
#' @examples
#' \dontrun{
#' runner <- sequential_workflow(list(
#'   writer   = agent("writer",   ellmer::chat_anthropic()),
#'   reviewer = agent("reviewer", ellmer::chat_anthropic())
#' ))
#' result <- runner$invoke(list(messages = list("Write a haiku.")))
#' }
sequential_workflow <- function(agents, state_schema = NULL) {
  if (!is.list(agents) || length(agents) == 0L) {
    cli::cli_abort("{.arg agents} must be a non-empty named list of {.cls Agent} objects.")
  }
  if (is.null(names(agents)) || any(names(agents) == "")) {
    cli::cli_abort("All agents in {.arg agents} must be named.")
  }

  if (is.null(state_schema)) {
    state_schema <- workflow_state(
      messages = list(default = list(), reducer = reducer_append())
    )
  }

  g <- state_graph(state_schema)

  agent_names <- names(agents)
  for (nm in agent_names) {
    local({
      agent_nm <- nm
      node_fn  <- function(state, config) {
        msgs <- state$get("messages")
        last <- if (length(msgs) > 0L) msgs[[length(msgs)]] else ""
        response <- config$agents[[agent_nm]]$chat(as.character(last))
        list(messages = response)
      }
      g$add_node(agent_nm, node_fn)
    })
  }

  g$add_edge(START, agent_names[[1L]])
  if (length(agent_names) > 1L) {
    for (i in seq_len(length(agent_names) - 1L)) {
      g$add_edge(agent_names[[i]], agent_names[[i + 1L]])
    }
  }
  g$add_edge(agent_names[[length(agent_names)]], END)

  g$compile(agents = agents)
}

#' Build a supervisor workflow
#'
#' Creates a hub-and-spoke graph: a manager agent directs work to worker agents
#' one at a time. The manager's response is expected to contain the name of the
#' next worker (or `"DONE"` to stop).
#'
#' @param manager An `Agent` object acting as the supervisor.
#' @param workers Named list of `Agent` objects.
#' @param max_rounds Integer. Maximum number of manager turns (default 10).
#' @param state_schema A [WorkflowState] or `NULL` (uses default).
#' @returns A compiled [GraphRunner].
#' @export
#' @examples
#' \dontrun{
#' runner <- supervisor_workflow(
#'   manager = agent("manager", ellmer::chat_anthropic(),
#'                   instructions = "Delegate to 'writer' or reply 'DONE'."),
#'   workers = list(writer = agent("writer", ellmer::chat_anthropic()))
#' )
#' result <- runner$invoke(list(messages = list("Write a short story.")))
#' }
supervisor_workflow <- function(manager, workers, max_rounds = 10L,
                                state_schema = NULL) {
  if (!inherits(manager, "Agent")) {
    cli::cli_abort("{.arg manager} must be an {.cls Agent} object.")
  }
  if (!is.list(workers) || length(workers) == 0L) {
    cli::cli_abort("{.arg workers} must be a non-empty named list of {.cls Agent} objects.")
  }

  worker_names <- names(workers)
  if (is.null(worker_names) || any(worker_names == "")) {
    cli::cli_abort("All workers must be named.")
  }

  if (is.null(state_schema)) {
    state_schema <- workflow_state(
      messages      = list(default = list(), reducer = reducer_append()),
      current_route = list(default = "")
    )
  }

  all_agents <- c(list(manager = manager), workers)

  g <- state_graph(state_schema)

  manager_fn <- function(state, config) {
    msgs <- state$get("messages")
    context <- paste(vapply(msgs, as.character, character(1)), collapse = "\n")
    response <- config$agents$manager$chat(context)
    list(messages = response, current_route = response)
  }
  g$add_node("manager", manager_fn)

  for (nm in worker_names) {
    local({
      worker_nm <- nm
      worker_fn <- function(state, config) {
        msgs <- state$get("messages")
        last <- if (length(msgs) > 0L) msgs[[length(msgs)]] else ""
        response <- config$agents[[worker_nm]]$chat(as.character(last))
        list(messages = response)
      }
      g$add_node(worker_nm, worker_fn)
      g$add_edge(worker_nm, "manager")
    })
  }

  route_map <- stats::setNames(as.list(worker_names), worker_names)
  route_map$DONE <- END

  routing_fn <- function(state) {
    route <- state$get("current_route")
    matched <- worker_names[vapply(
      worker_names,
      function(nm) grepl(nm, route, fixed = TRUE),
      logical(1)
    )]
    if (length(matched) > 0L) return(matched[[1L]])
    "DONE"
  }
  g$add_conditional_edge("manager", routing_fn, route_map)

  g$add_edge(START, "manager")

  g$compile(
    agents      = all_agents,
    termination = max_turns(max_rounds)
  )
}

#' Build a debate workflow
#'
#' Agents take turns in round-robin order responding to each other. An optional
#' judge agent decides when to stop.
#'
#' @param agents Named list of `Agent` objects participating in the debate.
#' @param max_rounds Integer. Number of full rounds (default 5).
#' @param judge An optional `Agent` that evaluates each round. If `NULL`,
#'   the workflow stops after `max_rounds * length(agents)` turns.
#' @param state_schema A [WorkflowState] or `NULL` (uses default).
#' @returns A compiled [GraphRunner].
#' @export
#' @examples
#' \dontrun{
#' runner <- debate_workflow(
#'   agents = list(
#'     pro  = agent("pro",  ellmer::chat_anthropic()),
#'     con  = agent("con",  ellmer::chat_anthropic())
#'   ),
#'   max_rounds = 3L
#' )
#' result <- runner$invoke(list(messages = list("Is R better than Python?")))
#' }
debate_workflow <- function(agents, max_rounds = 5L, judge = NULL,
                            state_schema = NULL) {
  if (!is.list(agents) || length(agents) < 2L) {
    cli::cli_abort("{.arg agents} must be a list of at least two {.cls Agent} objects.")
  }
  agent_names <- names(agents)
  if (is.null(agent_names) || any(agent_names == "")) {
    cli::cli_abort("All agents must be named.")
  }

  if (is.null(state_schema)) {
    state_schema <- workflow_state(
      messages = list(default = list(), reducer = reducer_append())
    )
  }

  all_agents <- agents
  if (!is.null(judge)) all_agents <- c(all_agents, list(judge = judge))

  g <- state_graph(state_schema)

  for (nm in agent_names) {
    local({
      agent_nm <- nm
      debate_fn <- function(state, config) {
        msgs <- state$get("messages")
        context <- paste(vapply(msgs, as.character, character(1)), collapse = "\n")
        response <- config$agents[[agent_nm]]$chat(context)
        list(messages = response)
      }
      g$add_node(agent_nm, debate_fn)
    })
  }

  g$add_edge(START, agent_names[[1L]])

  if (!is.null(judge)) {
    judge_fn <- function(state, config) {
      msgs <- state$get("messages")
      context <- paste(vapply(msgs, as.character, character(1)), collapse = "\n")
      verdict <- config$agents$judge$chat(
        paste0(context, "\n\nReply 'continue' or 'done'.")
      )
      list(messages = verdict, .judge_verdict = verdict)
    }
    g$add_node("judge", judge_fn)

    for (i in seq_along(agent_names)) {
      next_agent <- if (i < length(agent_names)) agent_names[[i + 1L]] else "judge"
      g$add_edge(agent_names[[i]], next_agent)
    }

    judge_route_map <- c(
      list(done = END),
      stats::setNames(list(agent_names[[1L]]), "continue")
    )
    g$add_conditional_edge(
      "judge",
      function(state) {
        verdict <- state$get("messages")
        last <- if (length(verdict) > 0L) verdict[[length(verdict)]] else ""
        if (grepl("done", tolower(as.character(last)), fixed = TRUE)) "done" else "continue"
      },
      judge_route_map
    )
  } else {
    for (i in seq_along(agent_names)) {
      next_node <- if (i < length(agent_names)) agent_names[[i + 1L]] else agent_names[[1L]]
      g$add_edge(agent_names[[i]], next_node)
    }
  }

  termination <- max_turns(max_rounds * length(agent_names))
  g$compile(agents = all_agents, termination = termination)
}
