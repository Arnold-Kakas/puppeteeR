# GraphRunner R6 class

The compiled, executable graph. Produced by
[StateGraph](StateGraph.md)`$compile()`. Do not call `GraphRunner$new()`
directly; use [StateGraph](StateGraph.md)`$compile()`.

## Value

The final [WorkflowState](WorkflowState.md) object.

A `coro` generator yielding `list(node, state_snapshot, iteration)`.

State snapshot (named list) or `NULL`.

A data frame with columns `agent`, `provider`, `model`, `input_tokens`,
`output_tokens`, `cost`.

## Methods

### Public methods

- [`GraphRunner$new()`](#method-GraphRunner-new)

- [`GraphRunner$invoke()`](#method-GraphRunner-invoke)

- [`GraphRunner$stream()`](#method-GraphRunner-stream)

- [`GraphRunner$get_state()`](#method-GraphRunner-get_state)

- [`GraphRunner$update_state()`](#method-GraphRunner-update_state)

- [`GraphRunner$cost_report()`](#method-GraphRunner-cost_report)

- [`GraphRunner$print()`](#method-GraphRunner-print)

- [`GraphRunner$clone()`](#method-GraphRunner-clone)

------------------------------------------------------------------------

### Method `new()`

Initialise the runner. Called internally by `StateGraph$compile()`.

#### Usage

    GraphRunner$new(
      nodes,
      edges,
      conditional_edges,
      state_schema,
      agents,
      checkpointer,
      termination
    )

#### Arguments

- `nodes`:

  Named list of `list(fn = <function>)`.

- `edges`:

  List of `list(from, to)`.

- `conditional_edges`:

  List of `list(from, routing_fn, route_map)`.

- `state_schema`:

  A [WorkflowState](WorkflowState.md) object (used as schema template).

- `agents`:

  Named list of `Agent` objects.

- `checkpointer`:

  A [Checkpointer](Checkpointer.md) or `NULL`.

- `termination`:

  A `termination_condition` or `NULL`.

------------------------------------------------------------------------

### Method `invoke()`

Execute the graph and return the final state.

#### Usage

    GraphRunner$invoke(initial_state = list(), config = list())

#### Arguments

- `initial_state`:

  Named list of initial channel overrides.

- `config`:

  Named list of run-time configuration:

  - `thread_id`: character, identifies this run for checkpointing.

  - `max_iterations`: integer, cycle guard (default 25).

  - `on_step`: `function(node_name, state)` callback after each node.

  - `verbose`: logical, print step info via `cli` (default `FALSE`).

------------------------------------------------------------------------

### Method `stream()`

Stream graph execution, yielding after each node.

#### Usage

    GraphRunner$stream(initial_state = list(), config = list())

#### Arguments

- `initial_state`:

  Named list of initial channel overrides.

- `config`:

  Named list (same keys as `$invoke()`).

------------------------------------------------------------------------

### Method `get_state()`

Retrieve the last checkpointed state for a thread.

#### Usage

    GraphRunner$get_state(thread_id)

#### Arguments

- `thread_id`:

  Character.

------------------------------------------------------------------------

### Method `update_state()`

Manually update a checkpointed state (human-in-the-loop).

#### Usage

    GraphRunner$update_state(thread_id, updates)

#### Arguments

- `thread_id`:

  Character.

- `updates`:

  Named list of channel updates.

------------------------------------------------------------------------

### Method `cost_report()`

Return a cost report across all agents.

#### Usage

    GraphRunner$cost_report()

------------------------------------------------------------------------

### Method [`print()`](https://rdrr.io/r/base/print.html)

Print runner summary.

#### Usage

    GraphRunner$print(...)

#### Arguments

- `...`:

  Ignored.

------------------------------------------------------------------------

### Method `clone()`

The objects of this class are cloneable with this method.

#### Usage

    GraphRunner$clone(deep = FALSE)

#### Arguments

- `deep`:

  Whether to make a deep clone.
