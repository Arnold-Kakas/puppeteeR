# Reducer: merge lists with `modifyList`

Performs a shallow merge of `new` into `old` using
[`modifyList()`](https://rdrr.io/r/utils/modifyList.html). Useful for
nested configuration state.

## Usage

``` r
reducer_merge()
```

## Value

A two-argument function `function(old, new)`.

## Examples

``` r
r <- reducer_merge()
r(list(a = 1, b = 2), list(b = 99, c = 3))
#> $a
#> [1] 1
#> 
#> $b
#> [1] 99
#> 
#> $c
#> [1] 3
#> 
```
