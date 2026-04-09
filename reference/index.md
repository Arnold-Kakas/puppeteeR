# Package index

## All functions

- [`agent()`](Agent.md) : Agent R6 class

- [`Checkpointer`](Checkpointer.md) : Checkpointer base class

- [`END`](END.md) : Sentinel: end of graph

- [`GraphRunner`](GraphRunner.md) : GraphRunner R6 class

- [`MemoryCheckpointer`](MemoryCheckpointer.md) : In-memory checkpointer

- [`RDSCheckpointer`](RDSCheckpointer.md) : RDS file-based checkpointer

- [`SQLiteCheckpointer`](SQLiteCheckpointer.md) : SQLite-based
  checkpointer

- [`START`](START.md) : Sentinel: start of graph

- [`StateGraph`](StateGraph.md) : StateGraph R6 class

- [`WorkflowState`](WorkflowState.md) : WorkflowState R6 class

- [`add_conditional_edge()`](add_conditional_edge.md) : Add a
  conditional edge to a graph

- [`add_edge()`](add_edge.md) : Add a fixed edge to a graph

- [`add_node()`](add_node.md) : Add a node to a graph

- [`check_termination()`](check_termination.md) : Evaluate a termination
  condition

- [`compile()`](compile.md) : Compile a StateGraph into a GraphRunner

- [`` `|`( ``*`<termination_condition>`*`)`](compose_termination.md)
  [`` `&`( ``*`<termination_condition>`*`)`](compose_termination.md) :
  Compose termination conditions

- [`cost_limit()`](cost_limit.md) : Termination condition: cost limit

- [`custom_condition()`](custom_condition.md) : Termination condition:
  custom function

- [`debate_workflow()`](debate_workflow.md) : Build a debate workflow

- [`max_turns()`](max_turns.md) : Termination condition: maximum
  iterations

- [`memory_checkpointer()`](memory_checkpointer.md) : Create an
  in-memory checkpointer

- [`rds_checkpointer()`](rds_checkpointer.md) : Create an RDS file
  checkpointer

- [`reducer_append()`](reducer_append.md) : Reducer: append new value to
  a list

- [`reducer_merge()`](reducer_merge.md) :

  Reducer: merge lists with `modifyList`

- [`reducer_overwrite()`](reducer_overwrite.md) : Reducer: overwrite
  channel with new value

- [`sequential_workflow()`](sequential_workflow.md) : Build a sequential
  workflow

- [`sqlite_checkpointer()`](sqlite_checkpointer.md) : Create a SQLite
  checkpointer

- [`state_graph()`](state_graph.md) : Create a StateGraph

- [`supervisor_workflow()`](supervisor_workflow.md) : Build a supervisor
  workflow

- [`text_match()`](text_match.md) : Termination condition: text pattern
  match

- [`workflow_state()`](workflow_state.md) : Create a WorkflowState
