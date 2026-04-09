# as_dot() snapshot is stable

    Code
      dot
    Output
      [1] "digraph workflow {\n  graph [rankdir=TB fontname=\"Helvetica\" bgcolor=\"transparent\"]\n  node  [shape=rect style=\"rounded,filled\" fontname=\"Helvetica\" fillcolor=\"#E8F0FE\" color=\"#4A90D9\"]\n  edge  [fontname=\"Helvetica\" fontsize=10 color=\"#666666\"]\n\n  __START__ [label=\"START\" shape=oval fillcolor=\"#2D3748\" fontcolor=white]\n  __END__   [label=\"END\"   shape=oval fillcolor=\"#2D3748\" fontcolor=white]\n  classify [label=\"classify\" fillcolor=\"#FFF3CD\"]\n  respond [label=\"respond\"]\n  __START__ -> classify\n  respond -> __END__\n  classify -> respond [label=\"respond\" style=dashed]\n  classify -> __END__ [label=\"done\" style=dashed]\n}"

