# Convenience Workflows

puppeteeR ships five one-liner constructors for common multi-agent
patterns. Each returns a compiled `GraphRunner` ready to invoke.

## `sequential_workflow()` - linear chain

Agents run in order. Each agent receives the previous agent’s response
as its input.

``` r
library(ellmer)

runner <- sequential_workflow(list(
  drafter  = agent("drafter",  chat_anthropic(),
                   instructions = "Write a first draft of the requested content."),
  reviewer = agent("reviewer", chat_anthropic(),
                   instructions = "Review the draft and suggest improvements."),
  polisher = agent("polisher", chat_anthropic(),
                   instructions = "Incorporate the review and produce a polished final version.")
))

result <- runner$invoke(list(messages = list("Write a short blog post about tidy data.")))

# All messages (input + all agent responses)
result$get("messages")
```

The default state schema has a single `messages` channel with
[`reducer_append()`](https://arnold-kakas.github.io/puppeteeR/reference/reducer_append.md).
Each agent’s response is appended, so the final state contains the full
conversation chain.

You can supply a custom schema if you need additional channels:

``` r
my_schema <- workflow_state(
  messages = list(default = list(), reducer = reducer_append()),
  topic    = list(default = "")
)

runner2 <- sequential_workflow(
  agents       = list(
    researcher = agent("researcher", chat_anthropic()),
    writer     = agent("writer",     chat_anthropic())
  ),
  state_schema = my_schema
)

result2 <- runner2$invoke(list(
  topic    = "reinforcement learning",
  messages = list("Write about reinforcement learning.")
))
```

## `supervisor_workflow()` - hub-and-spoke

A manager agent directs work to a pool of worker agents. After each
worker finishes, control returns to the manager. The manager ends the
workflow by replying `"DONE"`.

``` r
runner <- supervisor_workflow(
  manager = agent(
    "manager", chat_anthropic(),
    instructions = paste0(
      "You coordinate a team. Available workers: 'researcher', 'writer'.\n",
      "Reply with exactly one worker name to delegate, or 'DONE' when finished."
    )
  ),
  workers = list(
    researcher = agent("researcher", chat_anthropic(),
                       instructions = "Research the given topic and return bullet-point notes."),
    writer     = agent("writer",     chat_anthropic(),
                       instructions = "Turn research notes into a readable article.")
  ),
  max_rounds = 6L
)

result <- runner$invoke(list(messages = list("Produce an article on quantum computing.")))
result$get("messages")
```

**How routing works**: after each manager turn, the supervisor searches
the manager’s response text for a worker name. If none is found it
routes to `"DONE"`. The `max_rounds` safety valve limits total manager
turns.

**Tip**: prompt the manager explicitly to name exactly one worker per
turn. Ambiguous responses fall through to `"DONE"`.

## `debate_workflow()` - round-robin with optional judge

Agents take turns responding to each other in round-robin order. Useful
for exploring multiple perspectives on a question, stress-testing an
argument, or creative brainstorming.

### Without a judge

Runs for a fixed number of rounds then stops.

``` r
runner <- debate_workflow(
  agents = list(
    pro  = agent("pro",  chat_anthropic(),
                 instructions = "Argue in favour of the proposition."),
    con  = agent("con",  chat_anthropic(),
                 instructions = "Argue against the proposition.")
  ),
  max_rounds = 3L
)

result <- runner$invoke(list(
  messages = list("Proposition: R is better than Python for data science.")
))

# Print the debate transcript
for (msg in result$get("messages")) cat("---\n", as.character(msg), "\n")
```

### With a judge

After each full round, a judge agent decides whether the debate is
settled. The judge should reply `"continue"` or `"done"`.

``` r
runner <- debate_workflow(
  agents = list(
    optimist  = agent("optimist",  chat_anthropic(),
                      instructions = "Always highlight the positive side."),
    pessimist = agent("pessimist", chat_anthropic(),
                      instructions = "Always highlight risks and downsides.")
  ),
  judge = agent(
    "judge", chat_anthropic(),
    instructions = paste0(
      "Read the debate so far. If both sides have made their key points ",
      "and the debate is productive, reply 'done'. Otherwise reply 'continue'."
    )
  ),
  max_rounds = 5L
)

result <- runner$invoke(list(messages = list("Should we adopt AI in healthcare?")))
```

## `advisor_workflow()` — worker + advisor feedback loop

A cheap worker agent produces output; a higher-capability advisor agent
evaluates it and either approves it or sends it back with specific
feedback. This pattern minimises cost by running the expensive model
only for evaluation, not for generation.

``` r
runner <- advisor_workflow(
  worker  = agent(
    "writer", chat_anthropic(model = "claude-haiku-4-5-20251001"),
    instructions = "Write clearly and concisely."
  ),
  advisor = agent(
    "advisor", chat_anthropic(model = "claude-opus-4-6"),
    instructions = paste0(
      "You are a strict editor. If the response is accurate, well-structured, and concise, ",
      "reply 'approved'. Otherwise reply 'revise: <specific feedback>'."
    )
  ),
  max_revisions = 3L
)

result <- runner$invoke(list(messages = list("Explain what a closure is in R.")))

result$get("latest_draft")   # final approved text
result$get("revision_n")     # number of revision cycles needed
result$get("messages")       # full audit trail: task, drafts, advisor verdicts
```

**How routing works**: after each advisor turn, the workflow reads the
`advisor_verdict` channel (`"approved"` or `"revise"`). If approved,
execution ends. If revision is requested, the worker is called again
with the original task plus the advisor’s feedback appended.

**State channels**: `latest_draft` (overwrite) always holds the current
version — the advisor evaluates this, not the full message history.
`advisor_feedback` (overwrite) carries the most recent revision notes.
`messages` (append) is a full audit trail of every draft and verdict.

**Tip**: be explicit in the advisor’s instructions about the reply
format. The routing reads for a response that starts with `"approved"`
or `"revise:"` — a vague verdict like `"looks good"` will be treated as
a revision request.

## `planner_workflow()` — Opus plans, Haiku executes

Separates expensive planning and evaluation (Opus-tier) from cheap
execution (Haiku-tier). The planner creates a step-by-step plan once; a
pure-R dispatcher routes each step to the correct worker without any LLM
call; the evaluator decides whether the results are complete or need a
revised plan.

``` r
runner <- planner_workflow(
  planner = agent(
    "planner", chat_anthropic(model = "claude-opus-4-6"),
    instructions = paste0(
      "Break the task into steps for 'researcher' and 'writer'. ",
      "Respond with one step per line as: worker_name: instruction"
    )
  ),
  workers = list(
    researcher = agent(
      "researcher", chat_anthropic(model = "claude-haiku-4-5-20251001"),
      instructions = "Research thoroughly and return structured notes."
    ),
    writer = agent(
      "writer", chat_anthropic(model = "claude-haiku-4-5-20251001"),
      instructions = "Write clearly based on the provided notes."
    )
  ),
  evaluator = agent(
    "evaluator", chat_anthropic(model = "claude-opus-4-6"),
    instructions = paste0(
      "Review the completed work against the original task. ",
      "Reply 'done' if complete, or 'replan' with a brief reason if not."
    )
  ),
  max_replans = 2L,
  max_steps   = 6L
)

result <- runner$invoke(list(
  messages = list("Write a short report on the benefits of tidy data in R.")
))

result$get("results")   # list of all worker outputs, in order
```

**How the plan is parsed**: the planner must respond with one step per
line in the format `worker_name: instruction`. Lines that do not match
this format raise an error. A custom `parse_plan` function can be
supplied for alternative formats such as JSON:

``` r
parse_json_plan <- function(text) {
  steps <- jsonlite::fromJSON(as.character(text))
  lapply(seq_len(nrow(steps)), function(i) {
    list(worker = steps$worker[[i]], instruction = steps$instruction[[i]])
  })
}

runner2 <- planner_workflow(
  planner    = agent("planner", chat_anthropic(model = "claude-opus-4-6"),
                     instructions = "Respond with a JSON array of {worker, instruction} objects."),
  workers    = list(analyst = agent("analyst", chat_anthropic())),
  parse_plan = parse_json_plan
)
```

**Cost profile** for a plan with N steps and R replanning rounds:

| Model tier | Node        | Calls               |
|------------|-------------|---------------------|
| Opus       | planner     | `R + 1`             |
| Opus       | evaluator   | `R + 1`             |
| Haiku      | each worker | up to `N × (R + 1)` |

In a `supervisor_workflow` the manager (Opus) is called once *per step*.
In a `planner_workflow` Opus is called once *per round* regardless of
plan length — a meaningful saving for plans with many steps.

## Comparison

| Workflow                                                                                             | When to use                                                       |
|------------------------------------------------------------------------------------------------------|-------------------------------------------------------------------|
| [`sequential_workflow()`](https://arnold-kakas.github.io/puppeteeR/reference/sequential_workflow.md) | Fixed pipeline: each step refines the previous output             |
| [`supervisor_workflow()`](https://arnold-kakas.github.io/puppeteeR/reference/supervisor_workflow.md) | Dynamic delegation: manager decides which specialist to call next |
| [`debate_workflow()`](https://arnold-kakas.github.io/puppeteeR/reference/debate_workflow.md)         | Multiple perspectives: agents challenge each other                |
| `advisor_workflow()`                                                                                 | Quality gate: cheap model generates, expensive model approves     |
| `planner_workflow()`                                                                                 | Cost efficiency: expensive model plans once, cheap models execute |

For anything more complex — handoffs, parallel fans, custom state
channels — build the graph directly with
[`state_graph()`](https://arnold-kakas.github.io/puppeteeR/reference/state_graph.md).
See
[`vignette("custom-graphs")`](https://arnold-kakas.github.io/puppeteeR/articles/custom-graphs.md).
