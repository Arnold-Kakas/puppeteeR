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
      messages = list(default = list(), reducer = reducer_append()),
      output   = list(default = "")
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
        updates <- list(messages = response)
        if ("output" %in% state$keys()) updates$output <- as.character(response)
        updates
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

  g$compile(agents = agents, output_channel = "output")
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
      current_route = list(default = ""),
      output        = list(default = "")
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
        msgs    <- state$get("messages")
        context <- paste(vapply(msgs, as.character, character(1L)), collapse = "\n")
        response <- config$agents[[worker_nm]]$chat(context)
        list(messages = response, output = as.character(response))
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
    agents         = all_agents,
    termination    = max_turns(max_rounds),
    output_channel = "output"
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

  n_agents <- length(agent_names)

  if (is.null(state_schema)) {
    if (!is.null(judge)) {
      state_schema <- workflow_state(
        messages      = list(default = list(), reducer = reducer_append()),
        judge_verdict = list(default = "continue"),
        output        = list(default = "")
      )
    } else {
      state_schema <- workflow_state(
        messages = list(default = list(), reducer = reducer_append()),
        output   = list(default = list(), reducer = reducer_last_n(n_agents))
      )
    }
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
        list(messages = response, output = response)
      }
      g$add_node(agent_nm, debate_fn)
    })
  }

  g$add_edge(START, agent_names[[1L]])

  if (!is.null(judge)) {
    judge_fn <- function(state, config) {
      msgs    <- state$get("messages")
      context <- paste(vapply(msgs, as.character, character(1L)), collapse = "\n")
      verdict <- config$agents$judge$chat(
        paste0(context, "\n\nReply 'continue' or 'done'.")
      )
      verdict_str <- tolower(trimws(as.character(verdict)))
      is_done     <- grepl("done", verdict_str, fixed = TRUE)
      update <- list(
        messages      = verdict,
        judge_verdict = if (is_done) "done" else "continue"
      )
      if ("output" %in% state$keys()) {
        update$output <- if (is_done) as.character(verdict) else state$get("output")
      }
      update
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
      function(state) state$get("judge_verdict"),
      judge_route_map
    )
  } else {
    for (i in seq_along(agent_names)) {
      next_node <- if (i < length(agent_names)) agent_names[[i + 1L]] else agent_names[[1L]]
      g$add_edge(agent_names[[i]], next_node)
    }
  }

  termination <- max_turns(max_rounds * length(agent_names))
  has_output <- "output" %in% state_schema$keys()
  g$compile(
    agents         = all_agents,
    termination    = termination,
    output_channel = if (has_output) "output" else NULL
  )
}

#' Build an advisor workflow
#'
#' A single worker agent produces output; a higher-tier advisor agent evaluates
#' it and either approves or requests a revision. The worker revises until
#' approved or `max_revisions` is reached.
#'
#' Graph: `START -> worker -> advisor -> (approved -> END | revise -> worker)`.
#'
#' @param worker An `Agent` object that produces the draft (typically a
#'   lower-cost model such as Haiku).
#' @param advisor An `Agent` object that evaluates the draft (typically a
#'   higher-capability model such as Opus).
#' @param max_revisions Integer. Maximum number of revision cycles (default 3L).
#' @param state_schema A [WorkflowState] or `NULL` (uses default). The default
#'   schema provides: `messages` (append), `latest_draft` (overwrite),
#'   `advisor_feedback` (overwrite), `advisor_verdict` (overwrite),
#'   `revision_n` (overwrite).
#' @returns A compiled [GraphRunner].
#' @export
#' @examples
#' \dontrun{
#' runner <- advisor_workflow(
#'   worker  = agent("writer",  ellmer::chat_anthropic(model = "claude-haiku-4-5-20251001")),
#'   advisor = agent("advisor", ellmer::chat_anthropic(model = "claude-opus-4-6"))
#' )
#' result <- runner$invoke(list(messages = list("Write a concise explanation of R6 classes.")))
#' result$get("latest_draft")
#' }
advisor_workflow <- function(worker, advisor, max_revisions = 3L,
                              state_schema = NULL) {
  if (!inherits(worker, "Agent")) {
    cli::cli_abort("{.arg worker} must be an {.cls Agent} object.")
  }
  if (!inherits(advisor, "Agent")) {
    cli::cli_abort("{.arg advisor} must be an {.cls Agent} object.")
  }

  if (is.null(state_schema)) {
    state_schema <- workflow_state(
      messages         = list(default = list(), reducer = reducer_append()),
      latest_draft     = list(default = ""),
      advisor_feedback = list(default = ""),
      advisor_verdict  = list(default = "revise"),
      revision_n       = list(default = 0L)
    )
  }

  g <- state_graph(state_schema)

  worker_fn <- function(state, config) {
    msgs     <- state$get("messages")
    feedback <- state$get("advisor_feedback")
    task     <- if (length(msgs) > 0L) as.character(msgs[[1L]]) else ""

    prompt <- if (nchar(trimws(feedback)) > 0L) {
      paste0(
        "Task: ", task,
        "\n\nAdvisor feedback on your previous response:\n", feedback,
        "\n\nPlease revise your response accordingly."
      )
    } else {
      task
    }

    response <- config$agents$worker$chat(prompt)
    list(
      messages     = response,
      latest_draft = as.character(response),
      revision_n   = state$get("revision_n") + if (nchar(trimws(feedback)) > 0L) 1L else 0L
    )
  }
  g$add_node("worker", worker_fn)

  advisor_fn <- function(state, config) {
    msgs  <- state$get("messages")
    draft <- state$get("latest_draft")
    task  <- if (length(msgs) > 0L) as.character(msgs[[1L]]) else ""

    verdict_raw <- config$agents$advisor$chat(paste0(
      "Task: ", task,
      "\n\nDraft response:\n", draft,
      "\n\nEvaluate the draft. Reply with either:\n",
      "  'approved' - if it meets quality standards\n",
      "  'revise: <feedback>' - if it needs improvement"
    ))

    verdict_str <- tolower(trimws(as.character(verdict_raw)))
    is_approved <- startsWith(verdict_str, "approved")
    feedback    <- if (!is_approved) sub("^revise:\\s*", "", verdict_str) else ""

    list(
      messages         = verdict_raw,
      advisor_verdict  = if (is_approved) "approved" else "revise",
      advisor_feedback = feedback
    )
  }
  g$add_node("advisor", advisor_fn)

  g$add_edge(START, "worker")
  g$add_edge("worker", "advisor")
  g$add_conditional_edge(
    "advisor",
    function(state) state$get("advisor_verdict"),
    list(approved = END, revise = "worker")
  )

  g$compile(
    agents         = list(worker = worker, advisor = advisor),
    termination    = max_turns(2L * (max_revisions + 1L)),
    output_channel = "latest_draft"
  )
}

#' Build a planner workflow
#'
#' A high-tier planner agent creates a step-by-step plan; a pure-R dispatcher
#' routes each step to the appropriate worker agent (no LLM call per dispatch);
#' an optional evaluator agent decides whether the results are complete or
#' require replanning.
#'
#' Graph: `START -> planner -> dispatcher -> [workers] -> dispatcher -> ...
#' -> evaluator -> (done -> END | replan -> planner)`.
#'
#' The planner must respond with one step per line in the format
#' `worker_name: instruction`. A custom `parse_plan` function can be supplied
#' to handle alternative formats.
#'
#' @param planner An `Agent` object used for planning (typically a high-capability
#'   model such as Opus).
#' @param workers Named list of `Agent` objects that execute plan steps.
#' @param evaluator An optional `Agent` object that reviews completed results.
#'   If `NULL`, the workflow ends when the plan is exhausted.
#' @param max_replans Integer. Maximum number of replanning rounds (default 2L).
#' @param max_steps Integer. Expected maximum plan length, used to size the
#'   termination guard (default 10L).
#' @param parse_plan Optional `function(text)` that converts the planner's raw
#'   response into a list of `list(worker, instruction)` items. If `NULL`, a
#'   default line-by-line parser expecting `worker_name: instruction` is used.
#' @param state_schema A [WorkflowState] or `NULL` (uses default).
#' @returns A compiled [GraphRunner].
#' @export
#' @examples
#' \dontrun{
#' runner <- planner_workflow(
#'   planner   = agent("planner",    ellmer::chat_anthropic(model = "claude-opus-4-6"),
#'                     instructions = "Break tasks into steps for 'researcher' and 'writer'."),
#'   workers   = list(
#'     researcher = agent("researcher", ellmer::chat_anthropic(model = "claude-haiku-4-5-20251001")),
#'     writer     = agent("writer",     ellmer::chat_anthropic(model = "claude-haiku-4-5-20251001"))
#'   ),
#'   evaluator = agent("evaluator",  ellmer::chat_anthropic(model = "claude-opus-4-6"))
#' )
#' result <- runner$invoke(list(messages = list("Write a short report on tidy data.")))
#' result$get("results")
#' }
planner_workflow <- function(planner, workers, evaluator = NULL,
                              max_replans = 2L, max_steps = 10L,
                              parse_plan = NULL, state_schema = NULL) {
  if (!inherits(planner, "Agent")) {
    cli::cli_abort("{.arg planner} must be an {.cls Agent} object.")
  }
  if (!is.list(workers) || length(workers) == 0L) {
    cli::cli_abort("{.arg workers} must be a non-empty named list of {.cls Agent} objects.")
  }
  worker_names <- names(workers)
  if (is.null(worker_names) || any(worker_names == "")) {
    cli::cli_abort("All workers must be named.")
  }
  if (!is.null(evaluator) && !inherits(evaluator, "Agent")) {
    cli::cli_abort("{.arg evaluator} must be an {.cls Agent} object or NULL.")
  }

  if (is.null(parse_plan)) {
    parse_plan <- function(text) {
      lines <- strsplit(trimws(as.character(text)), "\n")[[1L]]
      lines <- lines[nchar(trimws(lines)) > 0L]
      lapply(lines, function(line) {
        parts <- strsplit(line, ":", fixed = TRUE)[[1L]]
        if (length(parts) < 2L) {
          cli::cli_abort(c(
            "Could not parse plan line: {.val {line}}.",
            "i" = "Expected format: {.code worker_name: instruction}"
          ))
        }
        list(
          worker      = trimws(parts[[1L]]),
          instruction = trimws(paste(parts[-1L], collapse = ":"))
        )
      })
    }
  }

  if (is.null(state_schema)) {
    state_schema <- workflow_state(
      messages            = list(default = list(), reducer = reducer_append()),
      plan                = list(default = list(), reducer = reducer_overwrite()),
      plan_index          = list(default = 0L),
      current_instruction = list(default = ""),
      current_worker      = list(default = ""),
      results             = list(default = list(), reducer = reducer_append()),
      evaluator_verdict   = list(default = ""),
      replan_count        = list(default = 0L)
    )
  }

  all_agents <- c(list(planner = planner), workers)
  if (!is.null(evaluator)) all_agents <- c(all_agents, list(evaluator = evaluator))

  g <- state_graph(state_schema)

  planner_fn <- function(state, config) {
    msgs         <- state$get("messages")
    replan_count <- state$get("replan_count")
    results      <- state$get("results")

    task_context <- paste(vapply(msgs, as.character, character(1L)), collapse = "\n")

    prompt <- if (replan_count > 0L) {
      results_str <- paste(vapply(results, as.character, character(1L)), collapse = "\n")
      paste0(
        "Original task:\n", task_context,
        "\n\nWork completed so far:\n", results_str,
        "\n\nThe evaluator requested a revision. Create an updated plan.",
        "\n\nRespond with one step per line: worker_name: instruction",
        "\nAvailable workers: ", paste(worker_names, collapse = ", ")
      )
    } else {
      paste0(
        task_context,
        "\n\nCreate a step-by-step plan to complete the task.",
        "\nRespond with one step per line: worker_name: instruction",
        "\nAvailable workers: ", paste(worker_names, collapse = ", ")
      )
    }

    response <- config$agents$planner$chat(prompt)
    steps    <- tryCatch(
      parse_plan(as.character(response)),
      error = function(e) cli::cli_abort(
        "Plan parsing failed: {conditionMessage(e)}", parent = e
      )
    )

    list(
      messages     = response,
      plan         = steps,
      plan_index   = 0L,
      replan_count = replan_count + 1L
    )
  }
  g$add_node("planner", planner_fn)

  dispatcher_fn <- function(state, config) {
    plan <- state$get("plan")
    idx  <- state$get("plan_index") + 1L
    if (idx <= length(plan)) {
      step <- plan[[idx]]
      list(
        current_instruction = step$instruction,
        current_worker      = step$worker,
        plan_index          = idx
      )
    } else {
      list(plan_index = idx)
    }
  }
  g$add_node("dispatcher", dispatcher_fn)

  for (nm in worker_names) {
    local({
      worker_nm <- nm
      worker_fn <- function(state, config) {
        instruction <- state$get("current_instruction")
        response    <- config$agents[[worker_nm]]$chat(as.character(instruction))
        list(messages = response, results = response)
      }
      g$add_node(worker_nm, worker_fn)
      g$add_edge(worker_nm, "dispatcher")
    })
  }

  if (!is.null(evaluator)) {
    evaluator_fn <- function(state, config) {
      msgs    <- state$get("messages")
      results <- state$get("results")
      task    <- if (length(msgs) > 0L) as.character(msgs[[1L]]) else ""

      results_str <- paste(vapply(results, as.character, character(1L)), collapse = "\n")

      verdict_raw <- config$agents$evaluator$chat(paste0(
        "Task: ", task,
        "\n\nCompleted work:\n", results_str,
        "\n\nAre these results sufficient? Reply 'done' if complete, ",
        "or 'replan' if revision is needed."
      ))

      verdict_str <- tolower(trimws(as.character(verdict_raw)))
      list(
        messages          = verdict_raw,
        evaluator_verdict = if (grepl("done", verdict_str, fixed = TRUE)) "done" else "replan"
      )
    }
    g$add_node("evaluator", evaluator_fn)

    g$add_conditional_edge(
      "evaluator",
      function(state) state$get("evaluator_verdict"),
      list(done = END, replan = "planner")
    )
  }

  dispatch_route_map <- stats::setNames(as.list(worker_names), worker_names)
  dispatch_route_map[["__evaluator__"]] <- if (!is.null(evaluator)) "evaluator" else END

  g$add_conditional_edge(
    "dispatcher",
    function(state) {
      plan <- state$get("plan")
      idx  <- state$get("plan_index")
      if (idx > length(plan)) return("__evaluator__")
      worker <- state$get("current_worker")
      if (!worker %in% names(dispatch_route_map)) {
        cli::cli_abort(
          "Plan step specifies unknown worker {.val {worker}}.",
          "i" = "Available workers: {.val {names(workers)}}"
        )
      }
      worker
    },
    dispatch_route_map
  )

  g$add_edge(START, "planner")
  g$add_edge("planner", "dispatcher")

  g$compile(
    agents         = all_agents,
    termination    = max_turns((max_replans + 1L) * (max_steps + 3L)),
    output_channel = "results"
  )
}
