# Termination condition: cost limit

Stops execution when the cumulative cost exceeds `dollars`.

## Usage

``` r
cost_limit(dollars)
```

## Arguments

- dollars:

  Numeric. Cost threshold in USD.

## Value

A `termination_condition` S3 object.

## Examples

``` r
cond <- cost_limit(1.00)
```
