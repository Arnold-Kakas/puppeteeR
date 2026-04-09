# Reducer: overwrite channel with new value

The default reducer. Every update replaces the old value entirely.

## Usage

``` r
reducer_overwrite()
```

## Value

A two-argument function `function(old, new)` that returns `new`.

## Examples

``` r
r <- reducer_overwrite()
r("old", "new")
#> [1] "new"
```
