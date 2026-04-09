# Termination condition: maximum iterations

Stops execution when the iteration counter reaches `n`.

## Usage

``` r
max_turns(n)
```

## Arguments

- n:

  Integer. Maximum number of node executions.

## Value

A `termination_condition` S3 object.

## Examples

``` r
cond <- max_turns(10L)
check_termination(cond, NULL, 10L, 0)
#> [1] TRUE
```
