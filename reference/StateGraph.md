# StateGraph R6 class

Builder for directed graphs of node functions. Nodes are named R
functions; edges are fixed or conditional routing rules. Call
`$compile()` to produce an executable
[GraphRunner](https://arnold-kakas.github.io/puppeteeR/reference/GraphRunner.md).

Use the pipe-friendly wrappers
[`add_node()`](https://arnold-kakas.github.io/puppeteeR/reference/add_node.md),
[`add_edge()`](https://arnold-kakas.github.io/puppeteeR/reference/add_edge.md),
and
[`add_conditional_edge()`](https://arnold-kakas.github.io/puppeteeR/reference/add_conditional_edge.md)
rather than `$`-methods directly.

## Value

A new `StateGraph` object.

Invisibly, `self` (for chaining with `|>`).

Invisibly, `self`.

Invisibly, `self`.

Invisibly, `self`.

A
[GraphRunner](https://arnold-kakas.github.io/puppeteeR/reference/GraphRunner.md)
object ready to execute.

Character string.

Character string.

Invisibly, `path`.

## Methods

### Public methods

- [`StateGraph$new()`](#method-StateGraph-new)

- [`StateGraph$add_node()`](#method-StateGraph-add_node)

- [`StateGraph$add_edge()`](#method-StateGraph-add_edge)

- [`StateGraph$add_conditional_edge()`](#method-StateGraph-add_conditional_edge)

- [`StateGraph$set_entry()`](#method-StateGraph-set_entry)

- [`StateGraph$compile()`](#method-StateGraph-compile)

- [`StateGraph$as_dot()`](#method-StateGraph-as_dot)

- [`StateGraph$as_mermaid()`](#method-StateGraph-as_mermaid)

- [`StateGraph$visualize()`](#method-StateGraph-visualize)

- [`StateGraph$export_diagram()`](#method-StateGraph-export_diagram)

- [`StateGraph$print()`](#method-StateGraph-print)

- [`StateGraph$clone()`](#method-StateGraph-clone)

------------------------------------------------------------------------

### Method `new()`

Create a new StateGraph.

#### Usage

    StateGraph$new(state_schema)

#### Arguments

- `state_schema`:

  A
  [WorkflowState](https://arnold-kakas.github.io/puppeteeR/reference/WorkflowState.md)
  object, or a named list that will be passed to
  [`workflow_state()`](https://arnold-kakas.github.io/puppeteeR/reference/workflow_state.md).

------------------------------------------------------------------------

### Method [`add_node()`](https://arnold-kakas.github.io/puppeteeR/reference/add_node.md)

Register a node function.

#### Usage

    StateGraph$add_node(name, fn)

#### Arguments

- `name`:

  Character. Unique node name.

- `fn`:

  Function with signature `function(state, config)` returning a named
  list of state updates.

------------------------------------------------------------------------

### Method [`add_edge()`](https://arnold-kakas.github.io/puppeteeR/reference/add_edge.md)

Add a fixed edge between two nodes.

#### Usage

    StateGraph$add_edge(from, to)

#### Arguments

- `from`:

  Node name or
  [START](https://arnold-kakas.github.io/puppeteeR/reference/START.md).

- `to`:

  Node name or
  [END](https://arnold-kakas.github.io/puppeteeR/reference/END.md).

------------------------------------------------------------------------

### Method [`add_conditional_edge()`](https://arnold-kakas.github.io/puppeteeR/reference/add_conditional_edge.md)

Add a conditional (routing) edge.

#### Usage

    StateGraph$add_conditional_edge(from, routing_fn, route_map)

#### Arguments

- `from`:

  Node name. Must already be registered.

- `routing_fn`:

  Function `function(state)` returning a character key present in
  `route_map`.

- `route_map`:

  Named list mapping routing keys to node names or
  [END](https://arnold-kakas.github.io/puppeteeR/reference/END.md).

------------------------------------------------------------------------

### Method `set_entry()`

Shortcut to set the graph entry node.

#### Usage

    StateGraph$set_entry(name)

#### Arguments

- `name`:

  Character. Must be a registered node.

------------------------------------------------------------------------

### Method [`compile()`](https://arnold-kakas.github.io/puppeteeR/reference/compile.md)

Validate and compile the graph into a
[GraphRunner](https://arnold-kakas.github.io/puppeteeR/reference/GraphRunner.md).

#### Usage

    StateGraph$compile(agents = list(), checkpointer = NULL, termination = NULL)

#### Arguments

- `agents`:

  Named list of `Agent` objects passed to node functions via
  `config$agents`.

- `checkpointer`:

  A
  [Checkpointer](https://arnold-kakas.github.io/puppeteeR/reference/Checkpointer.md)
  object or `NULL`.

- `termination`:

  A termination condition (from
  [`max_turns()`](https://arnold-kakas.github.io/puppeteeR/reference/max_turns.md)
  etc.) or `NULL`.

------------------------------------------------------------------------

### Method `as_dot()`

Generate a DOT language string for the graph.

#### Usage

    StateGraph$as_dot()

------------------------------------------------------------------------

### Method `as_mermaid()`

Generate a Mermaid diagram string.

#### Usage

    StateGraph$as_mermaid()

------------------------------------------------------------------------

### Method `visualize()`

Render a visualization.

#### Usage

    StateGraph$visualize(engine = c("dot", "visnetwork", "mermaid"))

#### Arguments

- `engine`:

  One of `"dot"`, `"visnetwork"`, or `"mermaid"`.

------------------------------------------------------------------------

### Method `export_diagram()`

Export the diagram to a file.

#### Usage

    StateGraph$export_diagram(path, width = 800L, height = 600L)

#### Arguments

- `path`:

  File path. Extension determines format (`.svg` or `.png`).

- `width`:

  Integer. Width in pixels (PNG only).

- `height`:

  Integer. Height in pixels (PNG only).

------------------------------------------------------------------------

### Method [`print()`](https://rdrr.io/r/base/print.html)

Print graph summary.

#### Usage

    StateGraph$print(...)

#### Arguments

- `...`:

  Ignored.

------------------------------------------------------------------------

### Method `clone()`

The objects of this class are cloneable with this method.

#### Usage

    StateGraph$clone(deep = FALSE)

#### Arguments

- `deep`:

  Whether to make a deep clone.
