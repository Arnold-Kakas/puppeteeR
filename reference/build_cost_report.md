# Build a cost report across agents

Aggregates token usage and cost from a named list of `Agent` objects.

## Usage

``` r
build_cost_report(agents)
```

## Arguments

- agents:

  Named list of `Agent` objects.

## Value

A data frame with columns `agent`, `input_tokens`, `output_tokens`,
`cost`, plus a final totals row.
