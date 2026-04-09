# Termination condition: text pattern match

Stops execution when the specified state channel contains a string
matching `pattern`.

## Usage

``` r
text_match(pattern, channel = "messages")
```

## Arguments

- pattern:

  Character. Passed to
  [`base::grepl()`](https://rdrr.io/r/base/grep.html).

- channel:

  Character. Name of the state channel to inspect.

## Value

A `termination_condition` S3 object.

## Examples

``` r
cond <- text_match("DONE", channel = "status")
```
