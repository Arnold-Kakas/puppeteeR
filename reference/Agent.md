# Agent R6 class

A thin, opinionated wrapper around an
[`ellmer::Chat`](https://ellmer.tidyverse.org/reference/Chat.html)
object. Adds identity (name, role), conversation management helpers, and
cumulative cost tracking. All LLM logic is delegated to `ellmer`.

## Usage

``` r
agent(
  name,
  chat,
  role = NULL,
  instructions = NULL,
  tools = list(),
  handoffs = character()
)
```

## Arguments

- name:

  Character. Unique identifier for this agent within a workflow.

- chat:

  An [`ellmer::Chat`](https://ellmer.tidyverse.org/reference/Chat.html)
  object (e.g.
  [`ellmer::chat_anthropic()`](https://ellmer.tidyverse.org/reference/chat_anthropic.html)).

- role:

  Character or `NULL`. Short role description.

- instructions:

  Character or `NULL`. Detailed system instructions.

- tools:

  List of
  [`ellmer::tool()`](https://ellmer.tidyverse.org/reference/tool.html)
  objects.

- handoffs:

  Character vector of agent names for handoffs.

## Value

A new `Agent` object.

The assistant's response as a character string.

Parsed R object matching `type`.

A `coro` generator yielding text chunks.

A new `Agent` with the same configuration but no turns.

List of turn objects from `ellmer`.

Numeric, total USD spent so far.

Named list with `input` and `output` integer elements.

An `Agent` R6 object.

## Functions

- `agent()`: Construct an `Agent` from an
  [`ellmer::Chat`](https://ellmer.tidyverse.org/reference/Chat.html)
  object.

## Active bindings

- `name`:

  Agent name (read-only).

- `role`:

  Agent role description (read-only).

- `handoffs`:

  Names of agents this agent may hand off to (read-only).

## Methods

### Public methods

- [`Agent$new()`](#method-Agent-new)

- [`Agent$chat()`](#method-Agent-chat)

- [`Agent$chat_structured()`](#method-Agent-chat_structured)

- [`Agent$stream()`](#method-Agent-stream)

- [`Agent$clone_fresh()`](#method-Agent-clone_fresh)

- [`Agent$get_turns()`](#method-Agent-get_turns)

- [`Agent$set_turns()`](#method-Agent-set_turns)

- [`Agent$get_cost()`](#method-Agent-get_cost)

- [`Agent$get_tokens()`](#method-Agent-get_tokens)

- [`Agent$print()`](#method-Agent-print)

- [`Agent$clone()`](#method-Agent-clone)

------------------------------------------------------------------------

### Method `new()`

Create a new Agent.

#### Usage

    Agent$new(
      name,
      chat,
      role = NULL,
      instructions = NULL,
      tools = list(),
      handoffs = character()
    )

#### Arguments

- `name`:

  Character. Unique identifier used in graph node configs.

- `chat`:

  An [`ellmer::Chat`](https://ellmer.tidyverse.org/reference/Chat.html)
  object (e.g. from
  [`ellmer::chat_anthropic()`](https://ellmer.tidyverse.org/reference/chat_anthropic.html)).

- `role`:

  Character or `NULL`. Short role description prepended to the system
  prompt.

- `instructions`:

  Character or `NULL`. Detailed instructions appended to the system
  prompt.

- `tools`:

  List of
  [`ellmer::tool()`](https://ellmer.tidyverse.org/reference/tool.html)
  objects to register on the chat.

- `handoffs`:

  Character vector of agent names this agent may hand off to.

------------------------------------------------------------------------

### Method [`chat()`](https://ellmer.tidyverse.org/reference/chat-any.html)

Send a message to the agent.

#### Usage

    Agent$chat(...)

#### Arguments

- `...`:

  Passed to `ellmer::Chat$chat()`.

------------------------------------------------------------------------

### Method `chat_structured()`

Send a message and receive a structured response.

#### Usage

    Agent$chat_structured(..., type)

#### Arguments

- `...`:

  Passed to `ellmer::Chat$chat_structured()`.

- `type`:

  An `ellmer` type specification for the structured output.

------------------------------------------------------------------------

### Method `stream()`

Stream a response from the agent.

#### Usage

    Agent$stream(...)

#### Arguments

- `...`:

  Passed to `ellmer::Chat$stream()`.

------------------------------------------------------------------------

### Method `clone_fresh()`

Create a fresh copy of this agent with empty conversation history.

#### Usage

    Agent$clone_fresh()

------------------------------------------------------------------------

### Method `get_turns()`

Return the current conversation turns.

#### Usage

    Agent$get_turns()

------------------------------------------------------------------------

### Method `set_turns()`

Replace the conversation turns.

#### Usage

    Agent$set_turns(turns)

#### Arguments

- `turns`:

  List of turn objects.

------------------------------------------------------------------------

### Method `get_cost()`

Return cumulative cost for this agent.

#### Usage

    Agent$get_cost()

------------------------------------------------------------------------

### Method `get_tokens()`

Return cumulative token counts.

#### Usage

    Agent$get_tokens()

------------------------------------------------------------------------

### Method [`print()`](https://rdrr.io/r/base/print.html)

Print a summary of the agent.

#### Usage

    Agent$print(...)

#### Arguments

- `...`:

  Ignored.

------------------------------------------------------------------------

### Method `clone()`

The objects of this class are cloneable with this method.

#### Usage

    Agent$clone(deep = FALSE)

#### Arguments

- `deep`:

  Whether to make a deep clone.

## Examples

``` r
if (FALSE) { # \dontrun{
ag <- agent(
  name = "researcher",
  chat = ellmer::chat_anthropic(),
  role = "Senior researcher",
  instructions = "Be thorough and cite sources."
)
} # }
```
