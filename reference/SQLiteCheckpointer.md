# SQLite-based checkpointer

Persists checkpoints in a SQLite database. Requires the `DBI` and
`RSQLite` packages.

## Value

`list(step, state)` or `NULL`.

State snapshot or `NULL`.

Character vector.

## Super class

[`puppeteeR::Checkpointer`](https://arnold-kakas.github.io/puppeteeR/reference/Checkpointer.md)
-\> `SQLiteCheckpointer`

## Methods

### Public methods

- [`SQLiteCheckpointer$new()`](#method-SQLiteCheckpointer-new)

- [`SQLiteCheckpointer$save()`](#method-SQLiteCheckpointer-save)

- [`SQLiteCheckpointer$load_latest()`](#method-SQLiteCheckpointer-load_latest)

- [`SQLiteCheckpointer$load_step()`](#method-SQLiteCheckpointer-load_step)

- [`SQLiteCheckpointer$list_threads()`](#method-SQLiteCheckpointer-list_threads)

- [`SQLiteCheckpointer$clone()`](#method-SQLiteCheckpointer-clone)

------------------------------------------------------------------------

### Method `new()`

Create a SQLite checkpointer.

#### Usage

    SQLiteCheckpointer$new(path)

#### Arguments

- `path`:

  Character. Path to the SQLite database file.

------------------------------------------------------------------------

### Method [`save()`](https://rdrr.io/r/base/save.html)

Save a snapshot.

#### Usage

    SQLiteCheckpointer$save(thread_id, step, state_snapshot)

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

    SQLiteCheckpointer$load_latest(thread_id)

#### Arguments

- `thread_id`:

  Character.

------------------------------------------------------------------------

### Method `load_step()`

Load snapshot at exact step.

#### Usage

    SQLiteCheckpointer$load_step(thread_id, step)

#### Arguments

- `thread_id`:

  Character.

- `step`:

  Integer.

------------------------------------------------------------------------

### Method `list_threads()`

Return all thread IDs.

#### Usage

    SQLiteCheckpointer$list_threads()

------------------------------------------------------------------------

### Method `clone()`

The objects of this class are cloneable with this method.

#### Usage

    SQLiteCheckpointer$clone(deep = FALSE)

#### Arguments

- `deep`:

  Whether to make a deep clone.
