#' Generate a DOT language string for a StateGraph
#'
#' @param graph A [StateGraph] object. Not used directly — the graph's private
#'   fields are passed via the remaining arguments.
#' @param nodes Named list of node specs.
#' @param edges List of fixed edge specs.
#' @param conditional_edges List of conditional edge specs.
#' @returns Character string in Graphviz DOT format.
#' @keywords internal
graph_as_dot <- function(graph, nodes, edges, conditional_edges) {
  dot <- c(
    'digraph workflow {',
    '  graph [rankdir=TB fontname="Helvetica" bgcolor="transparent"]',
    '  node  [shape=rect style="rounded,filled" fontname="Helvetica" fillcolor="#E8F0FE" color="#4A90D9"]',
    '  edge  [fontname="Helvetica" fontsize=10 color="#666666"]',
    '',
    '  __START__ [label="START" shape=oval fillcolor="#2D3748" fontcolor=white]',
    '  __END__   [label="END"   shape=oval fillcolor="#2D3748" fontcolor=white]'
  )

  cond_sources <- vapply(conditional_edges, function(e) e$from, character(1))

  for (nm in names(nodes)) {
    if (nm %in% cond_sources) {
      dot <- c(dot, sprintf('  %s [label="%s" fillcolor="#FFF3CD"]', nm, nm))
    } else {
      dot <- c(dot, sprintf('  %s [label="%s"]', nm, nm))
    }
  }

  for (e in edges) {
    from <- if (is_sentinel(e$from)) "__START__" else e$from
    to   <- if (is_sentinel(e$to))   "__END__"   else e$to
    dot  <- c(dot, sprintf("  %s -> %s", from, to))
  }

  for (ce in conditional_edges) {
    from <- ce$from
    for (key in names(ce$route_map)) {
      to <- ce$route_map[[key]]
      if (is_sentinel(to)) to <- "__END__"
      dot <- c(dot, sprintf(
        '  %s -> %s [label="%s" style=dashed]', from, to, key
      ))
    }
  }

  dot <- c(dot, "}")
  paste(dot, collapse = "\n")
}

#' Generate a Mermaid diagram string for a StateGraph
#'
#' @inheritParams graph_as_dot
#' @returns Character string in Mermaid flowchart format.
#' @keywords internal
graph_as_mermaid <- function(graph, nodes, edges, conditional_edges) {
  lines <- "graph TD"

  for (e in edges) {
    from <- if (is_sentinel(e$from)) "START((START))" else sprintf("%s[%s]", e$from, e$from)
    to   <- if (is_sentinel(e$to))   "END((END))"     else sprintf("%s[%s]", e$to, e$to)
    lines <- c(lines, sprintf("  %s --> %s", from, to))
  }

  for (ce in conditional_edges) {
    from <- sprintf("%s[%s]", ce$from, ce$from)
    for (key in names(ce$route_map)) {
      to <- ce$route_map[[key]]
      to_str <- if (is_sentinel(to)) "END((END))" else sprintf("%s[%s]", to, to)
      lines <- c(lines, sprintf('  %s -- "%s" --> %s', from, key, to_str))
    }
  }

  paste(lines, collapse = "\n")
}

#' Render a StateGraph visualization
#'
#' @param graph A [StateGraph] object.
#' @param engine Character. One of `"dot"`, `"visnetwork"`, `"mermaid"`.
#' @returns A widget or prints to console.
#' @keywords internal
visualize_graph <- function(graph, engine) {
  switch(engine,
    dot = {
      rlang::check_installed("DiagrammeR", reason = "to render DOT diagrams")
      DiagrammeR::grViz(graph$as_dot())
    },
    visnetwork = {
      rlang::check_installed("visNetwork", reason = "for interactive visualization")
      build_visnetwork(graph)
    },
    mermaid = {
      cat(graph$as_mermaid(), "\n")
    }
  )
}

#' Build a visNetwork widget from a StateGraph
#'
#' @param graph A [StateGraph] object.
#' @returns A `visNetwork` htmlwidget.
#' @keywords internal
build_visnetwork <- function(graph) {
  priv <- graph$.__enclos_env__$private
  node_names <- names(priv$.nodes)

  ids    <- c("__START__", node_names, "__END__")
  labels <- c("START",     node_names, "END")
  shapes <- c("circle",    rep("box", length(node_names)), "circle")
  fills  <- c("#2D3748",   rep("#E8F0FE", length(node_names)), "#2D3748")
  fcolors <- c("white",    rep("black", length(node_names)), "white")

  nodes_df <- data.frame(
    id         = ids,
    label      = labels,
    shape      = shapes,
    color.background = fills,
    font.color = fcolors,
    stringsAsFactors = FALSE
  )

  edge_rows <- list()

  for (e in priv$.edges) {
    from <- if (is_sentinel(e$from)) "__START__" else e$from
    to   <- if (is_sentinel(e$to))   "__END__"   else e$to
    edge_rows <- c(edge_rows, list(data.frame(
      from = from, to = to, label = "", dashes = FALSE,
      stringsAsFactors = FALSE
    )))
  }

  for (ce in priv$.conditional_edges) {
    for (key in names(ce$route_map)) {
      to <- ce$route_map[[key]]
      if (is_sentinel(to)) to <- "__END__"
      edge_rows <- c(edge_rows, list(data.frame(
        from = ce$from, to = to, label = key, dashes = TRUE,
        stringsAsFactors = FALSE
      )))
    }
  }

  edges_df <- if (length(edge_rows) > 0L) {
    do.call(rbind, edge_rows)
  } else {
    data.frame(
      from = character(0), to = character(0),
      label = character(0), dashes = logical(0),
      stringsAsFactors = FALSE
    )
  }

  visNetwork::visNetwork(nodes_df, edges_df) |>
    visNetwork::visHierarchicalLayout(direction = "UD") |>
    visNetwork::visOptions(highlightNearest = TRUE) |>
    visNetwork::visEdges(arrows = "to")
}

#' Export a StateGraph diagram to a file
#'
#' @param graph A [StateGraph] object.
#' @param path Character. Output path. Extension determines format (`.svg` or
#'   `.png`).
#' @param width Integer. Width in pixels (PNG only).
#' @param height Integer. Height in pixels (PNG only).
#' @returns Invisibly, `path`.
#' @keywords internal
export_diagram_impl <- function(graph, path, width = 800L, height = 600L) {
  rlang::check_installed("DiagrammeR",    reason = "to export diagrams")
  rlang::check_installed("DiagrammeRsvg", reason = "to export diagrams")

  svg_str <- DiagrammeRsvg::export_svg(DiagrammeR::grViz(graph$as_dot()))

  ext <- tolower(tools::file_ext(path))
  if (ext == "svg") {
    writeLines(svg_str, path)
  } else if (ext == "png") {
    rlang::check_installed("rsvg", reason = "to export PNG diagrams")
    rsvg::rsvg_png(charToRaw(svg_str), file = path, width = width, height = height)
  } else {
    cli::cli_abort("Unsupported format: {.val {ext}}. Use {.val .svg} or {.val .png}.")
  }

  invisible(path)
}
