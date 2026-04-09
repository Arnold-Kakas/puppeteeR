#' Build a cost report across agents
#'
#' Aggregates token usage and cost from a named list of `Agent` objects.
#'
#' @param agents Named list of `Agent` objects.
#' @returns A data frame with columns `agent`, `input_tokens`, `output_tokens`,
#'   `cost`, plus a final totals row.
#' @keywords internal
build_cost_report <- function(agents) {
  if (length(agents) == 0L) {
    return(data.frame(
      agent         = character(0),
      input_tokens  = integer(0),
      output_tokens = integer(0),
      cost          = numeric(0),
      stringsAsFactors = FALSE
    ))
  }

  rows <- lapply(agents, function(a) {
    tokens <- a$get_tokens()
    data.frame(
      agent         = a$name,
      input_tokens  = tokens$input,
      output_tokens = tokens$output,
      cost          = a$get_cost(),
      stringsAsFactors = FALSE
    )
  })

  result <- do.call(rbind, rows)

  totals <- data.frame(
    agent         = "TOTAL",
    input_tokens  = sum(result$input_tokens),
    output_tokens = sum(result$output_tokens),
    cost          = sum(result$cost),
    stringsAsFactors = FALSE
  )

  rbind(result, totals)
}
