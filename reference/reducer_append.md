# Reducer: append new value to a list

Wraps `new` in a [`list()`](https://rdrr.io/r/base/list.html) and
concatenates it to `old`. Useful for accumulating messages.

## Usage

``` r
reducer_append()
```

## Value

A two-argument function `function(old, new)`.

## Examples

``` r
r <- reducer_append()
r(list("a"), "b")
#> [[1]]
#> [1] "a"
#> 
#> [[2]]
#> [1] "b"
#> 
```
