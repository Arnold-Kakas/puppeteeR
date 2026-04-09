# Evaluate a termination condition

S3 generic called by
[GraphRunner](https://arnold-kakas.github.io/puppeteeR/reference/GraphRunner.md)
after each node execution. Implement this method to create custom
termination condition classes.

## Usage

``` r
check_termination(condition, state, iteration, total_cost)
```

## Arguments

- condition:

  A `termination_condition` object.

- state:

  A
  [WorkflowState](https://arnold-kakas.github.io/puppeteeR/reference/WorkflowState.md)
  object.

- iteration:

  Integer. Current iteration count.

- total_cost:

  Numeric. Cumulative cost so far.

## Value

Logical scalar; `TRUE` means stop.
