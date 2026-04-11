# Building Custom Multi-Agent Graphs

This vignette shows how to build non-trivial graphs: looping agents,
multi-agent pipelines with handoffs, and conditional branches that merge
back together.

## Pattern 1: Agent loop with termination condition

A single agent that keeps refining its output until a condition is met.
The graph cycles back on itself - guarded by
[`max_turns()`](https://arnold-kakas.github.io/puppeteeR/reference/max_turns.md)
so it can’t run forever.

``` r
schema <- workflow_state(
  task     = list(default = ""),
  draft    = list(default = ""),
  approved = list(default = FALSE)
)
```

``` r
library(ellmer)

writer <- agent("writer", chat_anthropic(), instructions = "Write a short paragraph on the task.")
critic <- agent("critic", chat_anthropic(),
                instructions = "Review the draft. Reply 'APPROVED' if good, else give feedback.")

runner <- state_graph(schema) |>
  add_node("write", function(state, config) {
    prompt <- paste0("Task: ", state$get("task"), "\n\nPrevious draft: ", state$get("draft"))
    list(draft = config$agents$writer$chat(prompt))
  }) |>
  add_node("review", function(state, config) {
    prompt <- paste0("Draft:\n", state$get("draft"))
    feedback <- config$agents$critic$chat(prompt)
    list(
      draft    = feedback,
      approved = grepl("APPROVED", feedback, fixed = TRUE)
    )
  }) |>
  add_edge(START, "write") |>
  add_edge("write", "review") |>
  add_conditional_edge(
    "review",
    routing_fn = function(s) if (isTRUE(s$get("approved"))) "done" else "revise",
    route_map  = list(done = END, revise = "write")
  ) |>
  compile(
    agents      = list(writer = writer, critic = critic),
    termination = max_turns(10L)   # safety valve
  )

result <- runner$invoke(list(task = "Explain what a neural network is."))
result$get("draft")
```

## Pattern 2: Linear pipeline - research → write → edit

Nodes can read outputs from previous nodes via state. Each node adds to
accumulated history.

``` r
pipeline_schema <- workflow_state(
  topic    = list(default = ""),
  research = list(default = ""),
  draft    = list(default = ""),
  final    = list(default = ""),
  log      = list(default = list(), reducer = reducer_append())
)
```

``` r
researcher <- agent("researcher", chat_anthropic(),
                    instructions = "Research the topic and list 5 key facts.")
writer     <- agent("writer", chat_anthropic(),
                    instructions = "Write a 2-paragraph article using the research notes.")
editor     <- agent("editor", chat_anthropic(),
                    instructions = "Polish the article for clarity and concision. Return only the improved text.")

runner <- state_graph(pipeline_schema) |>
  add_node("research", function(state, config) {
    notes <- config$agents$researcher$chat(state$get("topic"))
    list(research = notes, log = "research complete")
  }) |>
  add_node("write", function(state, config) {
    prompt <- paste0("Notes:\n", state$get("research"))
    draft <- config$agents$writer$chat(prompt)
    list(draft = draft, log = "draft written")
  }) |>
  add_node("edit", function(state, config) {
    final <- config$agents$editor$chat(state$get("draft"))
    list(final = final, log = "editing done")
  }) |>
  add_edge(START, "research") |>
  add_edge("research", "write") |>
  add_edge("write", "edit") |>
  add_edge("edit", END) |>
  compile(agents = list(researcher = researcher, writer = writer, editor = editor))

result <- runner$invoke(list(topic = "The history of the R programming language"))
cat(result$get("final"))
cat("\n\nSteps:", paste(unlist(result$get("log")), collapse = " → "))
```

## Pattern 3: Parallel fan-out (manual)

R is single-threaded, but you can simulate parallel agents by running
them sequentially in one node and merging results.

``` r
fanout_schema <- workflow_state(
  question  = list(default = ""),
  answers   = list(default = list(), reducer = reducer_overwrite()),
  consensus = list(default = "")
)
```

``` r
agent_a <- agent("a", chat_anthropic(), instructions = "Answer concisely.")
agent_b <- agent("b", chat_anthropic(), instructions = "Answer with examples.")
agent_c <- agent("c", chat_anthropic(), instructions = "Answer step-by-step.")
judge   <- agent("judge", chat_anthropic(),
                 instructions = "Given multiple answers, synthesise the best consensus.")

runner <- state_graph(fanout_schema) |>
  add_node("gather", function(state, config) {
    q <- state$get("question")
    ans_a <- config$agents$a$chat(q)
    ans_b <- config$agents$b$chat(q)
    ans_c <- config$agents$c$chat(q)
    list(answers = list(ans_a, ans_b, ans_c))
  }) |>
  add_node("synthesise", function(state, config) {
    answers <- state$get("answers")
    all_answers <- paste(
      vapply(seq_along(answers),
             function(i) paste0("Answer ", i, ":\n", answers[[i]]),
             character(1L)),
      collapse = "\n\n"
    )
    list(consensus = config$agents$judge$chat(all_answers))
  }) |>
  add_edge(START, "gather") |>
  add_edge("gather", "synthesise") |>
  add_edge("synthesise", END) |>
  compile(agents = list(a = agent_a, b = agent_b, c = agent_c, judge = judge))

result <- runner$invoke(list(question = "What makes good software architecture?"))
result$get("consensus")
```

## Pattern 4: Handoffs between specialists

Agents declare which other agents they can hand off to. A routing node
reads the response and dispatches accordingly.

``` r
triage <- agent(
  "triage", chat_anthropic(),
  instructions = "Classify the request as 'code', 'data', or 'general'. Reply with only that word."
)
coder   <- agent("coder",   chat_anthropic(), instructions = "You are a coding expert.")
analyst <- agent("analyst", chat_anthropic(), instructions = "You are a data analysis expert.")
general <- agent("general", chat_anthropic(), instructions = "You are a general assistant.")

schema <- workflow_state(
  request  = list(default = ""),
  category = list(default = ""),
  response = list(default = "")
)

runner <- state_graph(schema) |>
  add_node("triage", function(state, config) {
    cat <- config$agents$triage$chat(state$get("request"))
    list(category = trimws(tolower(cat)))
  }) |>
  add_node("code_agent",    function(state, config) {
    list(response = config$agents$coder$chat(state$get("request")))
  }) |>
  add_node("data_agent",    function(state, config) {
    list(response = config$agents$analyst$chat(state$get("request")))
  }) |>
  add_node("general_agent", function(state, config) {
    list(response = config$agents$general$chat(state$get("request")))
  }) |>
  add_edge(START, "triage") |>
  add_conditional_edge(
    "triage",
    routing_fn = function(s) {
      cat <- s$get("category")
      if (grepl("code", cat))    "code"
      else if (grepl("data", cat)) "data"
      else                          "general"
    },
    route_map = list(code = "code_agent", data = "data_agent", general = "general_agent")
  ) |>
  add_edge("code_agent",    END) |>
  add_edge("data_agent",    END) |>
  add_edge("general_agent", END) |>
  compile(agents = list(
    triage  = triage,
    coder   = coder,
    analyst = analyst,
    general = general
  ))

result <- runner$invoke(list(request = "How do I write a for loop in R?"))
result$get("response")
```

## Termination conditions

All termination conditions are composable with `|` (OR) and `&` (AND):

``` r
# Stop after 20 turns OR if cost exceeds $0.50
cond <- max_turns(20L) | cost_limit(0.50)

# Stop after 10 turns AND only if the status channel says "done"
cond2 <- max_turns(10L) & text_match("done", channel = "status")

# Custom logic
cond3 <- custom_condition(function(state) {
  length(state$get("answers")) >= 3L
})
```

## Cost tracking

After a run, inspect costs per agent:

``` r
runner$cost_report()
#>      agent input_tokens output_tokens     cost
#> 1 researcher         320           180  0.00049
#> 2     writer         512           340  0.00084
#> 3     editor         420           210  0.00063
#> 4      TOTAL        1252           730  0.00196
```
