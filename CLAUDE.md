# puppeteer

LLM multi-agent orchestrator for R, built on ellmer. Think LangGraph but idiomatic R — graph-based workflows where multiple LLM agents with different roles, tools, and providers collaborate on tasks.

## Project structure

```
R/                          # All source code
  agent.R                   # Agent R6 class (wraps ellmer Chat)
  state.R                   # WorkflowState R6 class (typed channels + reducers)
  graph.R                   # StateGraph R6 class (builder: nodes, edges, conditional edges)
  runner.R                  # GraphRunner R6 class (compiled executor)
  checkpointer.R            # Checkpointer classes (memory, rds, sqlite)
  termination.R             # TerminationCondition S3 classes (composable with | and &)
  viz.R                     # Visualization layer (DOT generation, visNetwork, runtime)
  workflows.R               # Convenience constructors (sequential, supervisor, debate)
  cost.R                    # Token/cost aggregation across agents
  utils.R                   # Internal helpers
  puppeteer-package.R       # Package-level docs
tests/testthat/             # Mirror R/ structure: test-agent.R, test-graph.R, etc.
  helper.R                  # Shared test helpers, mock Chat objects
  fixtures/                 # Recorded API responses for deterministic tests
inst/prompts/               # Prompt templates for ellmer::interpolate_package()
vignettes/                  # Getting started, custom graphs, visualization
```

## Commands

```bash
# Load package in dev mode
devtools::load_all()

# Run a single test file
testthat::test_file("tests/testthat/test-graph.R")

# Run all tests
devtools::test()

# Regenerate docs from roxygen2 comments
devtools::document()

# Full R CMD check
devtools::check()

# Lint
lintr::lint_package()
```

## Coding standards

- R6 classes for all stateful objects (Agent, WorkflowState, StateGraph, GraphRunner, Checkpointer)
- S3 classes for immutable value objects (TerminationCondition, reducers, edge specs)
- No code comments except roxygen2 docstrings. Code should be self-explanatory.
- Use `cli` for all user-facing messages (cli_inform, cli_warn, cli_abort). Never `message()`, `warning()`, or `stop()` directly.
- Use `rlang::check_required()`, `rlang::arg_match()` for argument validation
- Pipe style: base R pipe `|>`, not magrittr `%>%`
- String interpolation: `cli::cli_abort("Expected {.cls Agent}, got {.cls {class(x)}}")` — use cli's inline markup
- Private fields prefixed with dot: `private$.chat`, `private$.state`
- Active bindings for read-only access to private fields
- All exported functions and R6 methods must have roxygen2 docs with `@param`, `@returns`, `@examples`
- Keep files under 300 lines. Split if larger.

## Architecture rules

- Agent is a thin wrapper around ellmer::Chat. Do NOT reimplement LLM logic. Delegate everything to ellmer.
- The graph engine (StateGraph + GraphRunner) must be fully testable without any LLM calls. Node functions are plain R functions that take state and return updates — they can be mocked trivially.
- WorkflowState channels use reducer functions for merging updates. Default reducer is overwrite. `reducer_append()` for message accumulation.
- GraphRunner executes nodes in topological order, respecting conditional edges. Cycles are allowed (for agent loops) but guarded by `max_iterations`.
- All cost tracking piggybacks on `ellmer::Chat$get_cost()`. No custom token counting.
- Visualization functions generate DOT strings or visNetwork data frames — they do NOT depend on a running workflow. They work on the StateGraph structure itself.

## ellmer integration patterns

```r
# Creating an agent — always delegate to ellmer Chat
agent <- Agent$new(
  name = "researcher",
  chat = chat_anthropic(model = "claude-sonnet-4-5-20250929"),
  role = "Senior researcher",
  instructions = "Be thorough and cite sources.",
  tools = list(search_tool)
)

# Inside a node function — use the agent's chat method
research_node <- function(state, config) {
  result <- config$agents$researcher$chat(state$get("query"))
  list(research = result)
}

# Tool definition — use ellmer's tool()
search_tool <- tool(
  fn = function(query) { httr2::request(...) },
  description = "Search the web",
  arguments = list(query = type_string("Search query"))
)
```

## Testing strategy

- **Tier 1 (CRAN-safe)**: Graph engine tests with mock node functions. No network, no API keys. These must always pass.
- **Tier 2 (CI with secrets)**: Integration tests using recorded responses via helper mocks. Gated by `skip_if_no_api_key()`.
- **Tier 3 (manual)**: Live multi-agent workflows. Never run in CI. In `tests/testthat/manual/`.
- Use `testthat::local_mocked_bindings()` to replace ellmer's chat constructors in tests.
- Use `withr::local_envvar()` for environment isolation.
- Test file naming: `test-{source-file}.R` maps to `R/{source-file}.R`.
- Snapshot tests for visualization output (DOT strings, printed status).

## Common pitfalls

- ellmer's Chat$chat() auto-executes tool calls in a loop. If an agent has tools, a single $chat() call may trigger multiple LLM round-trips. Account for this in cost tracking.
- ellmer Chat objects are R6 (reference semantics). $clone() is shallow by default. Use $clone(deep = TRUE) when forking conversations.
- Chat$set_turns() replaces the entire conversation history. To fork from a point, clone first then set_turns().
- Conditional edge routing functions must return a string matching a key in the route_map. If they return an unexpected value, fail loudly with cli_abort.
- WorkflowState reducers are called on every update. reducer_append() on a messages channel will grow unboundedly. Consider trimming strategies for long workflows.

## Dependencies

Imports: ellmer (>= 0.4.0), R6, cli, rlang, coro (for streaming)
Suggests: testthat (>= 3.0.0), withr, DiagrammeR, visNetwork, RSQLite, DBI, igraph, covr, httptest2
