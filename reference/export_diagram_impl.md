# Export a StateGraph diagram to a file

Export a StateGraph diagram to a file

## Usage

``` r
export_diagram_impl(graph, path, width = 800L, height = 600L)
```

## Arguments

- graph:

  A [StateGraph](StateGraph.md) object.

- path:

  Character. Output path. Extension determines format (`.svg` or
  `.png`).

- width:

  Integer. Width in pixels (PNG only).

- height:

  Integer. Height in pixels (PNG only).

## Value

Invisibly, `path`.
