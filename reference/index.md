# Package index

## All functions

- [`agent()`](https://arnold-kakas.github.io/puppeteeR/reference/Agent.md)
  : Agent R6 class

- [`Checkpointer`](https://arnold-kakas.github.io/puppeteeR/reference/Checkpointer.md)
  : Checkpointer base class

- [`END`](https://arnold-kakas.github.io/puppeteeR/reference/END.md) :
  Sentinel: end of graph

- [`GraphRunner`](https://arnold-kakas.github.io/puppeteeR/reference/GraphRunner.md)
  : GraphRunner R6 class

- [`MemoryCheckpointer`](https://arnold-kakas.github.io/puppeteeR/reference/MemoryCheckpointer.md)
  : In-memory checkpointer

- [`RDSCheckpointer`](https://arnold-kakas.github.io/puppeteeR/reference/RDSCheckpointer.md)
  : RDS file-based checkpointer

- [`SQLiteCheckpointer`](https://arnold-kakas.github.io/puppeteeR/reference/SQLiteCheckpointer.md)
  : SQLite-based checkpointer

- [`START`](https://arnold-kakas.github.io/puppeteeR/reference/START.md)
  : Sentinel: start of graph

- [`StateGraph`](https://arnold-kakas.github.io/puppeteeR/reference/StateGraph.md)
  : StateGraph R6 class

- [`WorkflowState`](https://arnold-kakas.github.io/puppeteeR/reference/WorkflowState.md)
  : WorkflowState R6 class

- [`add_conditional_edge()`](https://arnold-kakas.github.io/puppeteeR/reference/add_conditional_edge.md)
  : Add a conditional edge to a graph

- [`add_edge()`](https://arnold-kakas.github.io/puppeteeR/reference/add_edge.md)
  : Add a fixed edge to a graph

- [`add_node()`](https://arnold-kakas.github.io/puppeteeR/reference/add_node.md)
  : Add a node to a graph

- [`check_termination()`](https://arnold-kakas.github.io/puppeteeR/reference/check_termination.md)
  : Evaluate a termination condition

- [`compile()`](https://arnold-kakas.github.io/puppeteeR/reference/compile.md)
  : Compile a StateGraph into a GraphRunner

- [`` `|`( ``*`<termination_condition>`*`)`](https://arnold-kakas.github.io/puppeteeR/reference/compose_termination.md)
  [`` `&`( ``*`<termination_condition>`*`)`](https://arnold-kakas.github.io/puppeteeR/reference/compose_termination.md)
  : Compose termination conditions

- [`cost_limit()`](https://arnold-kakas.github.io/puppeteeR/reference/cost_limit.md)
  : Termination condition: cost limit

- [`custom_condition()`](https://arnold-kakas.github.io/puppeteeR/reference/custom_condition.md)
  : Termination condition: custom function

- [`debate_workflow()`](https://arnold-kakas.github.io/puppeteeR/reference/debate_workflow.md)
  : Build a debate workflow

- [`max_turns()`](https://arnold-kakas.github.io/puppeteeR/reference/max_turns.md)
  : Termination condition: maximum iterations

- [`memory_checkpointer()`](https://arnold-kakas.github.io/puppeteeR/reference/memory_checkpointer.md)
  : Create an in-memory checkpointer

- [`rds_checkpointer()`](https://arnold-kakas.github.io/puppeteeR/reference/rds_checkpointer.md)
  : Create an RDS file checkpointer

- [`reducer_append()`](https://arnold-kakas.github.io/puppeteeR/reference/reducer_append.md)
  : Reducer: append new value to a list

- [`reducer_merge()`](https://arnold-kakas.github.io/puppeteeR/reference/reducer_merge.md)
  :

  Reducer: merge lists with `modifyList`

- [`reducer_overwrite()`](https://arnold-kakas.github.io/puppeteeR/reference/reducer_overwrite.md)
  : Reducer: overwrite channel with new value

- [`sequential_workflow()`](https://arnold-kakas.github.io/puppeteeR/reference/sequential_workflow.md)
  : Build a sequential workflow

- [`sqlite_checkpointer()`](https://arnold-kakas.github.io/puppeteeR/reference/sqlite_checkpointer.md)
  : Create a SQLite checkpointer

- [`state_graph()`](https://arnold-kakas.github.io/puppeteeR/reference/state_graph.md)
  : Create a StateGraph

- [`supervisor_workflow()`](https://arnold-kakas.github.io/puppeteeR/reference/supervisor_workflow.md)
  : Build a supervisor workflow

- [`text_match()`](https://arnold-kakas.github.io/puppeteeR/reference/text_match.md)
  : Termination condition: text pattern match

- [`workflow_state()`](https://arnold-kakas.github.io/puppeteeR/reference/workflow_state.md)
  : Create a WorkflowState
