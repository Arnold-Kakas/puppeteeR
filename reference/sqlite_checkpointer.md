# Create a SQLite checkpointer

Create a SQLite checkpointer

## Usage

``` r
sqlite_checkpointer(path)
```

## Arguments

- path:

  Character. Path to the SQLite database file.

## Value

A
[SQLiteCheckpointer](https://arnold-kakas.github.io/puppeteeR/reference/SQLiteCheckpointer.md)
object.

## Examples

``` r
if (FALSE) { # \dontrun{
cp <- sqlite_checkpointer(tempfile(fileext = ".sqlite"))
} # }
```
