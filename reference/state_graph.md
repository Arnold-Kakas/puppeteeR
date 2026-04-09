# Create a StateGraph

Create a StateGraph

## Usage

``` r
state_graph(state_schema)
```

## Arguments

- state_schema:

  A [WorkflowState](WorkflowState.md) or a named list of channel specs.

## Value

A [StateGraph](StateGraph.md) object.

## Examples

``` r
schema <- workflow_state(result = list(default = NULL))
g <- state_graph(schema)
```
