# Agent guide

Two different jobs land in this repo. Pick the one you're doing.

## Writing or generating Markdown

**→ [AUTHORING.md](AUTHORING.md)** is the grammar contract. Read it before
emitting Markdown this engine will render.

The short version, if you read nothing else: anything the engine doesn't
recognise **stays literal text** rather than erroring, so a mistake is silent.
And much of the grammar is conditional — extensions (`==highlight==`,
`~~strikethrough~~`, `::: … :::`) and directives (`@name`) only exist if the
host app registered them. When the host's configuration is unknown, stay in
the core grammar.

## Changing the engine

**→ [CONTRIBUTING.md](CONTRIBUTING.md)** for setup, design constraints, and
commit conventions, and **[ARCHITECTURE.md](ARCHITECTURE.md)** for how text
becomes an AST, tokens, and styled attributes.

Two constraints worth knowing before you start, both easy to violate by
accident:

- **Per-keystroke work is O(edit), not O(document).** Parsing and restyling are
  block-scoped. A change that walks the whole document on every keystroke is a
  regression even when tests pass.
- **The parser derives all geometry.** Extensions and directives declare syntax
  and schema; they never emit ranges.
