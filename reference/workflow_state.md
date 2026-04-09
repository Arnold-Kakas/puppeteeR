# Create a WorkflowState

Constructs a
[WorkflowState](https://arnold-kakas.github.io/puppeteeR/reference/WorkflowState.md)
from named channel specifications.

## Usage

``` r
workflow_state(...)
```

## Arguments

- ...:

  Named arguments, each a `list(default = <value>)` optionally with a
  `reducer` element. If `reducer` is absent,
  [`reducer_overwrite()`](https://arnold-kakas.github.io/puppeteeR/reference/reducer_overwrite.md)
  is used.

## Value

A
[WorkflowState](https://arnold-kakas.github.io/puppeteeR/reference/WorkflowState.md)
object.

## Examples

``` r
ws <- workflow_state(
  messages = list(default = list(), reducer = reducer_append()),
  status   = list(default = "pending")
)
ws$get("status")
#> [1] "pending"
```
