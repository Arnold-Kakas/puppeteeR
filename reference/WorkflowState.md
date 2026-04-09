# WorkflowState R6 class

Mutable shared state passed between graph nodes. Each named channel has
a default value and a reducer function that controls how updates are
merged.

## Value

A new `WorkflowState` object.

The current channel value.

Invisibly, `self`.

Invisibly, `self`.

Named list.

Invisibly, `self`.

Character vector.

## Active bindings

- `schema`:

  The raw schema list (read-only). Used by [GraphRunner](GraphRunner.md)
  to reconstruct a fresh state on each `$invoke()` call.

## Methods

### Public methods

- [`WorkflowState$new()`](#method-WorkflowState-new)

- [`WorkflowState$get()`](#method-WorkflowState-get)

- [`WorkflowState$set()`](#method-WorkflowState-set)

- [`WorkflowState$update()`](#method-WorkflowState-update)

- [`WorkflowState$snapshot()`](#method-WorkflowState-snapshot)

- [`WorkflowState$restore()`](#method-WorkflowState-restore)

- [`WorkflowState$keys()`](#method-WorkflowState-keys)

- [`WorkflowState$print()`](#method-WorkflowState-print)

- [`WorkflowState$clone()`](#method-WorkflowState-clone)

------------------------------------------------------------------------

### Method `new()`

Create a new WorkflowState.

#### Usage

    WorkflowState$new(schema)

#### Arguments

- `schema`:

  Named list where each element is
  `list(default = <value>, reducer = <function>)`. If `reducer` is
  omitted, [`reducer_overwrite()`](reducer_overwrite.md) is used.

------------------------------------------------------------------------

### Method [`get()`](https://rdrr.io/r/base/get.html)

Get the current value of a channel.

#### Usage

    WorkflowState$get(key)

#### Arguments

- `key`:

  Character. Channel name.

------------------------------------------------------------------------

### Method `set()`

Set (apply reducer to) a single channel.

#### Usage

    WorkflowState$set(key, value)

#### Arguments

- `key`:

  Character. Channel name.

- `value`:

  New value passed to the reducer.

------------------------------------------------------------------------

### Method [`update()`](https://rdrr.io/r/stats/update.html)

Apply a named list of updates to the state.

#### Usage

    WorkflowState$update(updates)

#### Arguments

- `updates`:

  Named list. Keys starting with `"."` are reserved and silently
  ignored. Unknown keys raise an error (typo protection).

------------------------------------------------------------------------

### Method `snapshot()`

Return a deep copy of the current state as a plain list.

#### Usage

    WorkflowState$snapshot()

------------------------------------------------------------------------

### Method `restore()`

Restore state from a snapshot.

#### Usage

    WorkflowState$restore(snap)

#### Arguments

- `snap`:

  Named list previously produced by `$snapshot()`.

------------------------------------------------------------------------

### Method `keys()`

Return the names of all channels.

#### Usage

    WorkflowState$keys()

------------------------------------------------------------------------

### Method [`print()`](https://rdrr.io/r/base/print.html)

Print a summary of the state.

#### Usage

    WorkflowState$print(...)

#### Arguments

- `...`:

  Ignored.

------------------------------------------------------------------------

### Method `clone()`

The objects of this class are cloneable with this method.

#### Usage

    WorkflowState$clone(deep = FALSE)

#### Arguments

- `deep`:

  Whether to make a deep clone.
