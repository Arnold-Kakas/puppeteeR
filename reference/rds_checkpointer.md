# Create an RDS file checkpointer

Create an RDS file checkpointer

## Usage

``` r
rds_checkpointer(dir)
```

## Arguments

- dir:

  Character. Directory to store `.rds` files.

## Value

An
[RDSCheckpointer](https://arnold-kakas.github.io/puppeteeR/reference/RDSCheckpointer.md)
object.

## Examples

``` r
if (FALSE) { # \dontrun{
cp <- rds_checkpointer(tempdir())
} # }
```
