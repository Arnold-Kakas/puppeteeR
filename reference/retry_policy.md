# Define a retry policy for a graph node

Passed to
[`add_node()`](https://arnold-kakas.github.io/puppeteeR/reference/add_node.md)
via the `retry` argument. When a node function throws an error, the
runner waits `wait_seconds` and retries up to `max_attempts` times
before re-throwing.

## Usage

``` r
retry_policy(max_attempts = 3L, wait_seconds = 1L, backoff = 1)
```

## Arguments

- max_attempts:

  Positive integer. Total number of attempts (including the first). Must
  be \>= 2.

- wait_seconds:

  Non-negative number. Seconds to wait between attempts. Each subsequent
  wait is multiplied by `backoff` (default 1 = no backoff).

- backoff:

  Positive number. Multiplier applied to `wait_seconds` after each
  failed attempt. Use `2` for exponential backoff.

## Value

An S3 object of class `retry_policy`.

## Examples

``` r
rp <- retry_policy(max_attempts = 3L, wait_seconds = 1L, backoff = 2)
```
