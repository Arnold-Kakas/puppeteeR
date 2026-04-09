---
paths:
  - "tests/**/*.R"
---

# Testing rules

- testthat 3rd edition. No `context()`.
- Test file naming: `test-{source-file}.R` mirrors `R/{source-file}.R`
- Three tiers:
  1. CRAN-safe: mock everything, no network. These are the default.
  2. CI-only: gated by `skip_if_no_api_key("ANTHROPIC_API_KEY")`. Use recorded responses where possible.
  3. Manual: in `tests/testthat/manual/`. Never run in CI.
- Use `local_mocked_bindings()` to stub ellmer chat constructors
- Use `withr::local_envvar()` for env isolation
- Use `expect_snapshot()` for DOT output, printed status, error messages
- Use `expect_s3_class()` not `expect_is()`
- Helper function `mock_agent(name, responses)` in `helper.R` returns an Agent with a fake Chat that returns canned responses in order
- Every R6 public method needs at least one test
- Test the graph engine exhaustively with plain R functions as nodes — no LLM needed
