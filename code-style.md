---
paths:
  - "R/**/*.R"
  - "tests/**/*.R"
---

# R code rules

- Use `cli_abort()`, `cli_warn()`, `cli_inform()` — never `stop()`, `warning()`, `message()`
- Use `rlang::check_required()` for mandatory args, `rlang::arg_match()` for enum args
- Base pipe `|>` only. No magrittr.
- No code comments. Roxygen2 docstrings only. If something needs explanation, the code needs refactoring.
- R6 private fields: `.name` pattern (dot prefix)
- Active bindings for read-only access
- Argument validation at the top of every public method, before any logic
- Return `invisible(self)` from R6 methods used for side effects (builder pattern)
- Every exported function needs `@export`, `@param` for each arg, `@returns`, and at least one `@examples`
- Use `rlang::check_installed()` before calling any Suggests dependency
- File naming: one primary class or concept per file. `agent.R` has Agent, `graph.R` has StateGraph.
