# Generate a DOT language string for a StateGraph

Generate a DOT language string for a StateGraph

## Usage

``` r
graph_as_dot(graph, nodes, edges, conditional_edges)
```

## Arguments

- graph:

  A [StateGraph](StateGraph.md) object. Not used directly — the graph's
  private fields are passed via the remaining arguments.

- nodes:

  Named list of node specs.

- edges:

  List of fixed edge specs.

- conditional_edges:

  List of conditional edge specs.

## Value

Character string in Graphviz DOT format.
