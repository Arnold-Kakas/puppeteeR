# Production Use Cases

puppeteeR fits best where workflows are **stateful, conditional, or
interruptible** — not where raw LLM throughput is the goal. R’s
single-threaded execution means agents run sequentially, which is
actually a feature in many real pipelines: each agent’s output informs
the next.

## 1. Document processing pipeline

**Problem**: Incoming reports, contracts, or emails must be classified,
extracted, and summarised before reaching analysts. Manual processing is
slow and inconsistent.

**Pattern**: Linear chain — classify → extract → summarise.

``` r
library(ellmer)

schema <- workflow_state(
  document       = list(default = ""),
  category       = list(default = ""),
  key_facts      = list(default = ""),
  summary        = list(default = ""),
  log            = list(default = list(), reducer = reducer_append())
)

classifier <- agent("classifier", chat_anthropic(),
  instructions = "Classify the document as: contract, report, invoice, or correspondence.
                  Return ONLY the category word.")

extractor <- agent("extractor", chat_anthropic(),
  instructions = "Extract the 5 most important facts from this document as a numbered list.")

summariser <- agent("summariser", chat_anthropic(),
  instructions = "Write a 2-sentence executive summary based on the category and key facts.")

runner <- state_graph(schema) |>
  add_node("classify", function(state, config) {
    cat <- config$agents$classifier$chat(state$get("document"))
    list(category = trimws(tolower(cat)), log = "classified")
  }) |>
  add_node("extract", function(state, config) {
    facts <- config$agents$extractor$chat(state$get("document"))
    list(key_facts = facts, log = "extracted")
  }) |>
  add_node("summarise", function(state, config) {
    prompt <- sprintf("Category: %s\n\nFacts:\n%s",
                      state$get("category"), state$get("key_facts"))
    list(summary = config$agents$summariser$chat(prompt), log = "summarised")
  }) |>
  add_edge(START, "classify") |>
  add_edge("classify", "extract") |>
  add_edge("extract", "summarise") |>
  add_edge("summarise", END) |>
  compile(agents = list(
    classifier = classifier,
    extractor  = extractor,
    summariser = summariser
  ))

result <- runner$invoke(list(
  document = "Q3 2024 Revenue Report: Total revenue €4.2M, up 18% YoY..."
))

cat(result$get("summary"))
```

**Why puppeteeR?** State is shared — the summariser sees both the
category and the extracted facts without re-reading the document. The
pipeline is resumable if any step fails.

------------------------------------------------------------------------

## 2. Email / ticket triage

**Problem**: A support inbox receives hundreds of messages daily. Urgent
items must be escalated, spam filtered, and routine queries routed to
the right team — all before a human reads them.

**Pattern**: Classify → route to specialist or discard.

``` r
schema <- workflow_state(
  email          = list(default = ""),
  classification = list(default = ""),
  draft_reply    = list(default = ""),
  approved       = list(default = FALSE)
)

classifier <- agent("classifier", chat_anthropic(),
  instructions = "Classify this support email as: urgent, billing, technical, or spam.
                  Return ONLY the label.")

support <- agent("support", chat_anthropic(),
  instructions = "Draft a helpful, professional reply to this support email.")

billing <- agent("billing", chat_anthropic(),
  instructions = "Draft a reply about billing. Be empathetic and offer a resolution path.")

runner <- state_graph(schema) |>
  add_node("classify", function(state, config) {
    label <- config$agents$classifier$chat(state$get("email"))
    list(classification = trimws(tolower(label)))
  }) |>
  add_node("support_reply", function(state, config) {
    list(draft_reply = config$agents$support$chat(state$get("email")))
  }) |>
  add_node("billing_reply", function(state, config) {
    list(draft_reply = config$agents$billing$chat(state$get("email")))
  }) |>
  add_node("discard", function(state, config) {
    list(draft_reply = "(spam — no reply sent)")
  }) |>
  add_edge(START, "classify") |>
  add_conditional_edge("classify",
    routing_fn = function(state) {
      cl <- state$get("classification")
      if (cl == "billing")  "billing"
      else if (cl == "spam") "spam"
      else                   "support"
    },
    route_map = list(support = "support_reply",
                     billing = "billing_reply",
                     spam    = "discard")
  ) |>
  add_edge("support_reply", END) |>
  add_edge("billing_reply", END) |>
  add_edge("discard",       END) |>
  compile(agents = list(
    classifier = classifier,
    support    = support,
    billing    = billing
  ))

result <- runner$invoke(list(
  email = "Hi, I was charged twice for my subscription this month..."
))
cat(result$get("draft_reply"))
```

------------------------------------------------------------------------

## 3. Automated report generation

**Problem**: Weekly or monthly reports require pulling analysis,
generating narrative, and formatting output — repetitive work that is
nonetheless high-stakes enough to need review.

**Pattern**: Research → draft → edit → human approval → publish.

``` r
schema <- workflow_state(
  topic    = list(default = ""),
  analysis = list(default = ""),
  draft    = list(default = ""),
  final    = list(default = ""),
  approved = list(default = FALSE)
)

cp <- memory_checkpointer()   # swap for rds_checkpointer() in production

runner <- state_graph(schema) |>
  add_node("analyse", function(state, config) {
    analysis <- config$agents$analyst$chat(
      paste("Analyse this topic with key statistics and trends:", state$get("topic"))
    )
    list(analysis = analysis)
  }) |>
  add_node("draft", function(state, config) {
    prompt <- paste("Write a 3-paragraph report based on this analysis:\n",
                    state$get("analysis"))
    list(draft = config$agents$writer$chat(prompt))
  }) |>
  add_node("edit", function(state, config) {
    prompt <- paste("Polish this report for clarity and concision:\n", state$get("draft"))
    list(final = config$agents$editor$chat(prompt))
  }) |>
  add_node("review", function(state, config) {
    cat("\n--- DRAFT FOR REVIEW ---\n", state$get("final"), "\n---\n")
    approved <- readline("Approve and publish? (y/n): ") == "y"
    list(approved = approved)
  }) |>
  add_edge(START, "analyse") |>
  add_edge("analyse", "draft") |>
  add_edge("draft", "edit") |>
  add_edge("edit", "review") |>
  add_conditional_edge("review",
    routing_fn = function(s) if (isTRUE(s$get("approved"))) "publish" else "redraft",
    route_map  = list(publish = END, redraft = "draft")
  ) |>
  compile(
    agents      = list(analyst = analyst, writer = writer, editor = editor),
    checkpointer = cp,
    termination  = max_turns(20L)
  )

result <- runner$invoke(
  list(topic = "R package download trends in 2024"),
  config = list(thread_id = "weekly-report-01")
)
```

**Why checkpointing?** Each step is expensive. If the session crashes
after “draft” but before “edit”, restarting resumes from the checkpoint
— the analyst’s work is not repeated.

------------------------------------------------------------------------

## 4. Code review assistant

**Problem**: Pull requests sit unreviewed because engineers are busy. An
LLM can provide a first pass — catching obvious issues, enforcing style,
and summarising changes — before human review.

**Pattern**: Supervisor delegates to specialist reviewers then
synthesises.

``` r
manager <- agent("manager", chat_anthropic(),
  instructions = "You coordinate code review. Available specialists:
    'security' (security vulnerabilities),
    'performance' (speed and memory),
    'style' (readability and conventions).
    Delegate to each one in turn, then reply 'DONE'.")

team <- supervisor_workflow(
  manager = manager,
  workers = list(
    security    = agent("security",    chat_anthropic(),
                        instructions = "Review for security issues: injection, exposure of secrets, unsafe eval."),
    performance = agent("performance", chat_anthropic(),
                        instructions = "Review for performance: vectorisation, memory, unnecessary copies."),
    style       = agent("style",       chat_anthropic(),
                        instructions = "Review for R style: naming, pipe usage, function length, documentation.")
  ),
  max_rounds = 6L
)

code <- '
user_data <- function(id) {
  query <- paste0("SELECT * FROM users WHERE id = ", id)
  dbGetQuery(con, query)
}
'

result <- team$invoke(list(messages = list(code)))

for (msg in result$get("messages")) cat("---\n", as.character(msg), "\n")
```

------------------------------------------------------------------------

## 5. Multi-turn data analysis

**Problem**: Exploratory data analysis requires iteration — a hypothesis
is formed, tested, and revised. LLM agents can participate in this loop
alongside human analysts.

**Pattern**: Analyst proposes approach → coder implements → analyst
interprets → loop.

``` r
schema <- workflow_state(
  data_description = list(default = ""),
  hypothesis       = list(default = ""),
  r_code           = list(default = ""),
  result           = list(default = ""),
  conclusion       = list(default = ""),
  messages         = list(default = list(), reducer = reducer_append())
)

analyst <- agent("analyst", chat_anthropic(),
  instructions = "You are a statistician. Propose a specific analytical hypothesis
                  and the R code needed to test it. Be precise.")

interpreter <- agent("interpreter", chat_anthropic(),
  instructions = "Given a hypothesis and result output, state whether the hypothesis
                  is supported and what it implies. Reply 'CONCLUDE' when analysis is complete.")

runner <- state_graph(schema) |>
  add_node("hypothesise", function(state, config) {
    prompt <- paste("Dataset:", state$get("data_description"),
                    "\nPrevious findings:", state$get("conclusion"))
    response <- config$agents$analyst$chat(prompt)
    list(hypothesis = response, messages = response)
  }) |>
  add_node("interpret", function(state, config) {
    prompt <- sprintf("Hypothesis: %s\n\nResult: %s",
                      state$get("hypothesis"), state$get("result"))
    conclusion <- config$agents$interpreter$chat(prompt)
    list(conclusion = conclusion, messages = conclusion)
  }) |>
  add_edge(START, "hypothesise") |>
  add_edge("hypothesise", "interpret") |>
  add_conditional_edge("interpret",
    routing_fn = function(s) {
      if (grepl("CONCLUDE", s$get("conclusion"), fixed = TRUE)) "done" else "continue"
    },
    route_map = list(done = END, continue = "hypothesise")
  ) |>
  compile(
    agents      = list(analyst = analyst, interpreter = interpreter),
    termination = max_turns(10L) | cost_limit(2.00)
  )
```

------------------------------------------------------------------------

## When puppeteeR is the right choice

| Scenario                                            | Fits?   | Reason                                                  |
|-----------------------------------------------------|---------|---------------------------------------------------------|
| Multi-step pipelines where each step feeds the next | Yes     | State management + checkpointing                        |
| Conditional routing based on content                | Yes     | Conditional edges                                       |
| Human approval mid-workflow                         | Yes     | Sequential execution is required                        |
| Long-running pipelines that may crash               | Yes     | Checkpointing enables resume                            |
| Repetitive batch processing of many documents       | Partial | Wrap `invoke()` in a loop; add `future` for parallelism |
| Real-time API serving (\<100 ms)                    | No      | Use a Python service                                    |
| Pure single-call LLM inference                      | No      | Call `ellmer` directly                                  |

## Parallelism with `future`

For true parallel LLM calls (e.g. calling three reviewers
simultaneously), combine with the `future` package inside a single node:

``` r
library(future)
plan(multisession, workers = 3L)

add_node("parallel_review", function(state, config) {
  code <- state$get("code")

  f_security    <- future(config$agents$security$chat(code))
  f_performance <- future(config$agents$performance$chat(code))
  f_style       <- future(config$agents$style$chat(code))

  list(
    security_review    = value(f_security),
    performance_review = value(f_performance),
    style_review       = value(f_style)
  )
})
```

Note that LLM API rate limits often throttle requests before parallelism
provides significant gains.
