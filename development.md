# Local development workflow (Positron)

Positron does not have a Build pane, but supports the same keyboard shortcuts as RStudio for package development.

## Keyboard shortcuts

| Action | Windows/Linux | Mac |
|---|---|---|
| `devtools::load_all()` | `Ctrl+Shift+L` | `Cmd+Shift+L` |
| `devtools::test()` | `Ctrl+Shift+T` | `Cmd+Shift+T` |
| `devtools::document()` | `Ctrl+Shift+D` | `Cmd+Shift+D` |
| `devtools::check()` | `Ctrl+Shift+E` | `Cmd+Shift+E` |

These work from anywhere — a source file, the console, wherever focus is.

## Console workflow

```r
# 1. Restore renv dependencies (once, or after renv.lock changes)
renv::restore()

# 2. Load the package into your session
devtools::load_all()

# 3. Run all tests
devtools::test()

# 4. Run a single test file (faster during dev)
testthat::test_file("tests/testthat/test-graph.R")

# 5. Regenerate docs after editing roxygen2 comments
devtools::document()

# 6. Full check (slow, run before committing)
devtools::check()
```

## Recommended dev loop

1. Edit a file in `R/`
2. `Ctrl+Shift+L` — reloads all source instantly
3. Call the function interactively in the console to poke at it
4. `Ctrl+Shift+T` — run tests
5. Repeat

No need to restart R between changes — `load_all()` handles it.

## Smoke test (no API key needed)

Paste into the console after `load_all()`:

```r
schema <- workflow_state(
  n   = list(default = 0L),
  out = list(default = list(), reducer = reducer_append())
)

runner <- state_graph(schema) |>
  add_node("double", function(s, cfg) list(n = s$get("n") * 2L, out = s$get("n"))) |>
  add_node("addten", function(s, cfg) list(n = s$get("n") + 10L, out = s$get("n"))) |>
  add_edge(START, "double") |>
  add_edge("double", "addten") |>
  add_edge("addten", END) |>
  compile()

final <- runner$invoke(list(n = 5L))
final$get("n")    # 20
final$get("out")  # list(5, 10)
```

## .Rprofile

Your `.Rprofile` only activates renv. Add this so `devtools` is auto-available in interactive sessions and the keyboard shortcuts work without explicitly loading it:

```r
source("renv/activate.R")

if (interactive()) {
  suppressMessages(require(devtools))
}
```
