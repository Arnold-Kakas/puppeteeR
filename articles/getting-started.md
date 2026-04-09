# Getting Started with puppeteeR

puppeteeR is an LLM multi-agent orchestrator for R built on
[ellmer](https://ellmer.tidyverse.org). It lets you define directed
graphs where each node is an R function (or an LLM agent) that reads
shared state, does work, and writes updates back. Think LangGraph, but
idiomatic R.

## Core concepts

| Concept         | What it is                                                                                                              |
|-----------------|-------------------------------------------------------------------------------------------------------------------------|
| `WorkflowState` | Mutable key-value store shared across all nodes                                                                         |
| `StateGraph`    | Builder for the graph (nodes + edges)                                                                                   |
| `GraphRunner`   | Compiled, executable graph returned by [`compile()`](https://arnold-kakas.github.io/puppeteeR/reference/compile.md)     |
| `Agent`         | Thin wrapper around an [`ellmer::Chat`](https://ellmer.tidyverse.org/reference/Chat.html) with identity + cost tracking |

## 1. Define state

Every graph has a **state schema** - a named set of channels, each with
a default value and an optional reducer that controls how updates merge.

``` r
schema <- workflow_state(
  input   = list(default = ""),
  result  = list(default = NULL),
  history = list(default = list(), reducer = reducer_append())
)
```

Three built-in reducers:

- [`reducer_overwrite()`](https://arnold-kakas.github.io/puppeteeR/reference/reducer_overwrite.md) -
  default, replaces old value with new value
- [`reducer_append()`](https://arnold-kakas.github.io/puppeteeR/reference/reducer_append.md) -
  wraps new value in a list and appends to old list (great for message
  history)
- [`reducer_merge()`](https://arnold-kakas.github.io/puppeteeR/reference/reducer_merge.md) -
  shallow-merges named lists with
  [`modifyList()`](https://rdrr.io/r/utils/modifyList.html)

## 2. Build the graph

Nodes are plain R functions with the signature
`function(state, config)`. They return a named list of channel updates.

``` r
runner <- state_graph(schema) |>
  add_node("process", function(state, config) {
    val <- toupper(state$get("input"))
    list(result = val, history = val)
  }) |>
  add_node("enrich", function(state, config) {
    prev <- state$get("result")
    list(result = paste0("[", prev, "]"), history = "enriched")
  }) |>
  add_edge(START, "process") |>
  add_edge("process", "enrich") |>
  add_edge("enrich", END) |>
  compile()
```

The pipe chain ends with
[`compile()`](https://arnold-kakas.github.io/puppeteeR/reference/compile.md),
which validates the graph and returns a `GraphRunner`.

## 3. Run it

``` r
final <- runner$invoke(list(input = "hello world"))

final$get("result")
#> [1] "[HELLO WORLD]"
final$get("history")
#> [[1]]
#> [1] "HELLO WORLD"
#> 
#> [[2]]
#> [1] "enriched"
```

`invoke()` accepts an `initial_state` list that overrides channel
defaults for this run.

## 4. Conditional routing

Return a key from a routing function to choose the next node
dynamically.

``` r
schema2 <- workflow_state(
  n   = list(default = 0L),
  out = list(default = "")
)

runner2 <- state_graph(schema2) |>
  add_node("check", function(s, cfg) list()) |>
  add_node("big",   function(s, cfg) list(out = "big number")) |>
  add_node("small", function(s, cfg) list(out = "small number")) |>
  add_edge(START, "check") |>
  add_conditional_edge(
    from       = "check",
    routing_fn = function(s) if (s$get("n") > 10L) "big" else "small",
    route_map  = list(big = "big", small = "small")
  ) |>
  add_edge("big",   END) |>
  add_edge("small", END) |>
  compile()

runner2$invoke(list(n = 3L))$get("out")
#> [1] "small number"
runner2$invoke(list(n = 99L))$get("out")
#> [1] "big number"
```

## 5. Adding an LLM agent

Agents wrap
[`ellmer::Chat`](https://ellmer.tidyverse.org/reference/Chat.html)
objects. Pass them to
[`compile()`](https://arnold-kakas.github.io/puppeteeR/reference/compile.md)
and access them inside nodes via `config$agents`.

``` r
library(ellmer)

researcher <- agent(
  name         = "researcher",
  chat         = chat_anthropic(model = "claude-haiku-4-5"),
  role         = "Senior researcher",
  instructions = "Give concise, factual answers."
)

schema3 <- workflow_state(
  query  = list(default = ""),
  answer = list(default = "")
)

runner3 <- state_graph(schema3) |>
  add_node("respond", function(state, config) {
    ans <- config$agents$researcher$chat(state$get("query"))
    list(answer = ans)
  }) |>
  add_edge(START, "respond") |>
  add_edge("respond", END) |>
  compile(agents = list(researcher = researcher))

result <- runner3$invoke(list(query = "What is the speed of light?"))
result$get("answer")
```

## 6. Streaming execution

`stream()` returns a `coro` generator that yields after each node -
useful for showing progress.

``` r
gen <- runner3$stream(list(query = "Explain quantum entanglement briefly."))
coro::loop(for (step in gen) {
  cat("Node:", step$node, "| iteration:", step$iteration, "\n")
})
```

## Next steps

- **Custom graphs**: conditional loops, multi-agent collaboration →
  [`vignette("custom-graphs")`](https://arnold-kakas.github.io/puppeteeR/articles/custom-graphs.md)
- **Convenience workflows**: one-liner sequential / supervisor / debate
  →
  [`vignette("workflows")`](https://arnold-kakas.github.io/puppeteeR/articles/workflows.md)
- **Checkpointing**: resume interrupted runs, human-in-the-loop →
  [`vignette("checkpointing")`](https://arnold-kakas.github.io/puppeteeR/articles/checkpointing.md)
- **Visualization**: render graph diagrams →
  [`vignette("visualization")`](https://arnold-kakas.github.io/puppeteeR/articles/visualization.md)
