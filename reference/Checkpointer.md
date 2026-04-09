# Checkpointer base class

Abstract interface for persisting workflow state. Concrete subclasses:
[MemoryCheckpointer](MemoryCheckpointer.md),
[RDSCheckpointer](RDSCheckpointer.md),
[SQLiteCheckpointer](SQLiteCheckpointer.md).

## Value

`list(step = <int>, state = <list>)` or `NULL`.

State snapshot list or `NULL`.

Character vector.

## Methods

### Public methods

- [`Checkpointer$save()`](#method-Checkpointer-save)

- [`Checkpointer$load_latest()`](#method-Checkpointer-load_latest)

- [`Checkpointer$load_step()`](#method-Checkpointer-load_step)

- [`Checkpointer$list_threads()`](#method-Checkpointer-list_threads)

- [`Checkpointer$clone()`](#method-Checkpointer-clone)

------------------------------------------------------------------------

### Method [`save()`](https://rdrr.io/r/base/save.html)

Save a state snapshot.

#### Usage

    Checkpointer$save(thread_id, step, state_snapshot)

#### Arguments

- `thread_id`:

  Character. Identifies the workflow run.

- `step`:

  Integer. Current step number.

- `state_snapshot`:

  Named list from `WorkflowState$snapshot()`.

------------------------------------------------------------------------

### Method `load_latest()`

Load the most recent snapshot for a thread.

#### Usage

    Checkpointer$load_latest(thread_id)

#### Arguments

- `thread_id`:

  Character.

------------------------------------------------------------------------

### Method `load_step()`

Load a snapshot at an exact step.

#### Usage

    Checkpointer$load_step(thread_id, step)

#### Arguments

- `thread_id`:

  Character.

- `step`:

  Integer.

------------------------------------------------------------------------

### Method `list_threads()`

List all thread IDs that have checkpoints.

#### Usage

    Checkpointer$list_threads()

------------------------------------------------------------------------

### Method `clone()`

The objects of this class are cloneable with this method.

#### Usage

    Checkpointer$clone(deep = FALSE)

#### Arguments

- `deep`:

  Whether to make a deep clone.
