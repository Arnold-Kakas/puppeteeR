# In-memory checkpointer

Stores checkpoints in a named list in RAM. State is lost when the R
session ends. Suitable for development, testing, and short workflows.

## Value

`list(step, state)` or `NULL`.

State snapshot or `NULL`.

Character vector.

## Super class

[`puppeteeR::Checkpointer`](Checkpointer.md) -\> `MemoryCheckpointer`

## Methods

### Public methods

- [`MemoryCheckpointer$new()`](#method-MemoryCheckpointer-new)

- [`MemoryCheckpointer$save()`](#method-MemoryCheckpointer-save)

- [`MemoryCheckpointer$load_latest()`](#method-MemoryCheckpointer-load_latest)

- [`MemoryCheckpointer$load_step()`](#method-MemoryCheckpointer-load_step)

- [`MemoryCheckpointer$list_threads()`](#method-MemoryCheckpointer-list_threads)

- [`MemoryCheckpointer$clone()`](#method-MemoryCheckpointer-clone)

------------------------------------------------------------------------

### Method `new()`

Initialise an empty in-memory store.

#### Usage

    MemoryCheckpointer$new()

------------------------------------------------------------------------

### Method [`save()`](https://rdrr.io/r/base/save.html)

Save a snapshot.

#### Usage

    MemoryCheckpointer$save(thread_id, step, state_snapshot)

#### Arguments

- `thread_id`:

  Character.

- `step`:

  Integer.

- `state_snapshot`:

  Named list.

------------------------------------------------------------------------

### Method `load_latest()`

Load the latest snapshot.

#### Usage

    MemoryCheckpointer$load_latest(thread_id)

#### Arguments

- `thread_id`:

  Character.

------------------------------------------------------------------------

### Method `load_step()`

Load snapshot at exact step.

#### Usage

    MemoryCheckpointer$load_step(thread_id, step)

#### Arguments

- `thread_id`:

  Character.

- `step`:

  Integer.

------------------------------------------------------------------------

### Method `list_threads()`

Return all thread IDs.

#### Usage

    MemoryCheckpointer$list_threads()

------------------------------------------------------------------------

### Method `clone()`

The objects of this class are cloneable with this method.

#### Usage

    MemoryCheckpointer$clone(deep = FALSE)

#### Arguments

- `deep`:

  Whether to make a deep clone.
