# Reducer: keep only the last `n` entries

Appends `new` to `old` then trims the list to at most `n` entries by
dropping the oldest. Use this instead of
[`reducer_append()`](https://arnold-kakas.github.io/puppeteeR/reference/reducer_append.md)
whenever the channel feeds into an LLM call, to prevent the context
window from growing unboundedly and causing connection errors on long
workflows.

## Usage

``` r
reducer_last_n(n)
```

## Arguments

- n:

  Positive integer. Maximum number of entries to retain.

## Value

A two-argument function `function(old, new)`.

## Examples

``` r
r <- reducer_last_n(3L)
r(list("a", "b", "c"), "d")   # drops "a", keeps "b", "c", "d"
#> [[1]]
#> [1] "b"
#> 
#> [[2]]
#> [1] "c"
#> 
#> [[3]]
#> [1] "d"
#> 
```
