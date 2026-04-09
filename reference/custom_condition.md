# Termination condition: custom function

Stops execution when `fn(state)` returns `TRUE`.

## Usage

``` r
custom_condition(fn)
```

## Arguments

- fn:

  Function `function(state)` returning a scalar logical.

## Value

A `termination_condition` S3 object.

## Examples

``` r
cond <- custom_condition(function(state) state$get("done") == TRUE)
```
