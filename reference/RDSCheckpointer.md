# RDS file-based checkpointer

Persists each checkpoint as an `.rds` file under
`{dir}/{thread_id}/step_{n}.rds`.

## Value

`list(step, state)` or `NULL`.

State snapshot or `NULL`.

Character vector.

## Super class

[`puppeteeR::Checkpointer`](Checkpointer.md) -\> `RDSCheckpointer`

## Methods

### Public methods

- [`RDSCheckpointer$new()`](#method-RDSCheckpointer-new)

- [`RDSCheckpointer$save()`](#method-RDSCheckpointer-save)

- [`RDSCheckpointer$load_latest()`](#method-RDSCheckpointer-load_latest)

- [`RDSCheckpointer$load_step()`](#method-RDSCheckpointer-load_step)

- [`RDSCheckpointer$list_threads()`](#method-RDSCheckpointer-list_threads)

- [`RDSCheckpointer$clone()`](#method-RDSCheckpointer-clone)

------------------------------------------------------------------------

### Method `new()`

Create an RDS checkpointer.

#### Usage

    RDSCheckpointer$new(dir)

#### Arguments

- `dir`:

  Character. Directory path where checkpoints are written.

------------------------------------------------------------------------

### Method [`save()`](https://rdrr.io/r/base/save.html)

Save a snapshot as an RDS file.

#### Usage

    RDSCheckpointer$save(thread_id, step, state_snapshot)

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

    RDSCheckpointer$load_latest(thread_id)

#### Arguments

- `thread_id`:

  Character.

------------------------------------------------------------------------

### Method `load_step()`

Load snapshot at exact step.

#### Usage

    RDSCheckpointer$load_step(thread_id, step)

#### Arguments

- `thread_id`:

  Character.

- `step`:

  Integer.

------------------------------------------------------------------------

### Method `list_threads()`

Return all thread IDs.

#### Usage

    RDSCheckpointer$list_threads()

------------------------------------------------------------------------

### Method `clone()`

The objects of this class are cloneable with this method.

#### Usage

    RDSCheckpointer$clone(deep = FALSE)

#### Arguments

- `deep`:

  Whether to make a deep clone.
