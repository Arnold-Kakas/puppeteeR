# Compose termination conditions

Combine two termination conditions with `|` (OR) or `&` (AND).

## Usage

``` r
# S3 method for class 'termination_condition'
a | b

# S3 method for class 'termination_condition'
a & b
```

## Arguments

- a, b:

  `termination_condition` objects.

## Value

A composite `termination_condition` object.

## Examples

``` r
cond <- max_turns(10L) | cost_limit(1.0)
cond2 <- max_turns(10L) & text_match("done", channel = "status")
```
