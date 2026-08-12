# Writing Markdown for this engine

A reference for agents (and people) generating documents this editor will
render. It covers the whole grammar: CommonMark-ish core, the bundled
extensions, and the directive seam.

Every claim below was checked against the parser rather than written from the
source, so the "stays literal" rows are as reliable as the "works" rows.

## The one rule that explains most surprises

**Anything the engine doesn't recognise stays literal text.** It is never an
error, never dropped, never half-rendered. A construct you got slightly wrong
appears verbatim on screen, which is the failure mode you want but also means
a typo is silent — no warning tells you `@fnot(size: 18){x}` didn't work.

Two things are *conditionally* recognised, and this trips up generators:

- **Extensions** (`==highlight==`, `~~strikethrough~~`, `::: containers :::`)
  only work if the embedding app registered them.
- **Directives** (`@name`) only work if that specific name was registered.

So `==hi==` renders as a highlight in an app that registered
`HighlightExtension`, and as the literal five characters `==hi==` in one that
didn't. **If you don't know how the host app is configured, restrict yourself
to the core grammar below.**

---

## Core: block level

A document is a flat sequence of blocks. Blank lines separate them.

| Block | Write it as | Notes |
|---|---|---|
| Heading | `# H1` … `###### H6` | 1–6 `#`, **then a space**. Up to 3 leading spaces allowed. No `===` underline form. |
| Paragraph | any other text | |
| Blockquote | `> quoted` | Up to 3 leading spaces, then `>`. |
| Unordered list | `- item`, `* item`, `+ item` | **A space must follow the marker.** |
| Ordered list | `1. item`, `1) item` | Up to 9 digits, then `.` or `)`, then a space. |
| Task list | `- [ ] todo`, `- [x] done` | A list item whose content starts with the checkbox. |
| Fenced code | ` ```lang ` … ` ``` ` | Opaque — nothing inside is parsed. |
| Block math | `$$ … $$` | Opaque. Line must start with `$$`. |
| Table | GFM, **outer pipes required** | See below. |
| Thematic break | `---`, `***`, `___` | 3 or more of **one** character, nothing else on the line. |

### Things that bite

**A bare marker is not a list.** `-` alone, or `1.` with nothing after, stays
literal. The space is mandatory.

**Tables need leading and trailing pipes on every row.** This is stricter than
GFM proper:

```markdown
| Name | Qty |
|------|-----|
| Bolt | 12  |
```

Dropping the outer pipes (`Name | Qty`) produces a paragraph, not a table. The
separator row may contain only `-`, `:`, `|`, and whitespace.

**An unclosed ` ``` ` fence stays literal** rather than swallowing the rest of
the document. Always emit the closing fence.

**Ordered list numbers are display-only.** The engine renumbers by position, so
`1. 1. 1.` renders as 1, 2, 3. Write whatever you like; the file keeps your
digits.

**A list item's continuation line ends the run.** Multi-line items switch
numbering off below them — prefer one line per item.

---

## Core: inline

| Construct | Write it as | Notes |
|---|---|---|
| Emphasis | `*italic*`, `_italic_` | |
| Strong | `**bold**` | |
| Both | `***bold italic***` | |
| Code span | `` `code` `` | Highest precedence. Opaque. |
| Link | `[text](url)` | Label is parsed; balanced parens in the URL are fine. |
| Image | `![alt](url)` | Alt text is opaque. |
| Wiki link | `[[Name]]`, `[[Name\|id]]` | Single line only. |
| Image embed | `![[target]]` | |
| Inline math | `$x^2$` | Heuristic — see below. |
| Escape | `\*`, `` \` ``, `\{` … | Makes the next ASCII punctuation literal. |

### Precedence

Code spans → escapes → links/images/wiki/embeds/math → emphasis. Earlier
passes win, so ``  `[a](b)` `` is a code span containing literal text, not a
link.

### Inline math is guessed, not declared

`$…$` only becomes math if the content looks mathematical. `$50` and
`$1,000.50` stay as currency text. Short all-letter content (≤3 chars) counts
as math; otherwise the content needs enough math-ish characters. **If you need
reliable math, use a `$$…$$` block.**

### Link labels may contain code and escapes

```markdown
[`App.swift`](/tmp/App.swift:56)
```

works. A code span **crossing** the label boundary (`` [a `b](c)` ``) rejects
the link and stays a code span.

### Bare URLs

`https://example.com` is auto-linked on screen and on copy. You don't need
`<angle brackets>`; there is no autolink syntax to write.

---

## Extensions (opt-in — confirm before using)

Registered by the host app via `MarkdownEditorConfiguration.extensions`.
Unregistered, every one of these is literal text.

| Extension | Syntax | Ships as |
|---|---|---|
| Highlight | `==text==` | `HighlightExtension` |
| Strikethrough | `~~text~~` | `StrikethroughExtension` |
| Container | `::: … :::` (fenced block) | `ContainerExtension` |

Inline extension content is parsed, so `==a **b**==` nests. The container
fence keeps full inline parsing inside, and — unlike a code fence — an unclosed
`:::` does not swallow the document.

---

## Directives (opt-in, per name)

The engine's own addition: named inline commands with typed arguments, for
things delimiters can't express. Registered via
`MarkdownEditorConfiguration.directives`.

### Shape

```
@name                          self-contained, no arguments
@name(arg)                     self-contained with arguments
@name(label: value){body}      container — body is parsed as markdown
```

The marker defaults to `@` and is configurable, so a host may use something
else. **A directive's form is fixed by its declaration**: a container directive
written without `{body}` stays literal, and a self-contained one written *with*
a body also stays literal.

### Name and argument rules

- Names are `[A-Za-z_][A-Za-z0-9_-]*`.
- Arguments are comma-separated. `label: value` is labelled; bare is positional.
- **Quote any value containing a comma, colon, or space**: `family: "Times New Roman"`.
- Parens, brackets and braces nest, so `{}` inside a body is fine when balanced.
- Value kinds: string, number, length, boolean (`true`/`false`), keyword.
- Lengths accept a bare number (points), `pt`, `em`, or `%` — `18`, `18pt`,
  `1.5em`, `120%`. Relative units resolve against the surrounding text.

### The two hard limits

**Single line.** A newline anywhere inside a directive — arguments or body —
rejects it. Directives never span lines.

**No escapes inside the body.** `@font(size: 18){a \} b}` stays literal,
because the escape pass claims before directives. This matches links
(`[a \* b](url)`) and highlights (`==a \* b==`), which behave the same way. If
you need a literal brace in a body, you currently can't — restructure instead.

### Where directives may appear

A directive opens only after a non-word character, so `name@example.com` is
never a directive. It composes normally otherwise: `*@font(size: 18){x}*`
nests inside emphasis, and list items and headings are fine. Inside a code
span or fence it is literal, like everything else.

### Bundled directives

Both are off by default and only present if the app registers them.

```markdown
@font(size: 18){larger}
@font(size: 1.5em, weight: bold){relative and bold}
@font(family: "Menlo"){monospaced}
@color(red){warning}
```

- **`@font`** — container. `size` (length), `family` (string),
  `weight` (`regular`|`bold`). Composes with surrounding style, so
  `@font(size: 18){**bold**}` is both bold and 18pt.
- **`@color`** — container, one required positional colour. Standard names:
  `red orange yellow green mint teal cyan blue indigo purple pink brown gray grey`.
  A host may also resolve its own asset-catalog names.

The demo app adds `@icon`, `@flag`, `@emoji`, and `@pagebreak` as examples of
embedder-supplied directives. **Do not assume these exist** — they are not part
of the engine.

---

## Verified behaviour

Each row was run through the parser to produce this table.

| Input | Result |
|---|---|
| `@font(size: 18){hi}` | directive |
| `@font(size: 1.5em){hi}` | directive |
| `@font(size: 120%){hi}` | directive |
| `@font(family: "Times New Roman"){hi}` | directive |
| `@color(red){hi}` | directive |
| `@font(size: 18)` | **literal** — container needs a body |
| `@nope(1){x}` | **literal** — name not registered |
| `mail name@example.com here` | **literal** — email is safe |
| `@font(size: 18){a \} b}` | **literal** — escape in body |
| `@font(size: 18){line⏎break}` | **literal** — newline |
| `` `@font(size: 18){x}` `` | code span |
| `*@font(size: 18){x}*` | italic containing the directive |
| `==hi==` (registered) | highlight |
| `==hi==` (not registered) | **literal** |
| ``[`App`](/p.swift:5)`` | link with a code span in the label |
| `$x^2$` | math |
| `$50` | **literal** — currency, not math |
| `[[Note\|uuid]]` | wiki link |
| `![[img.png]]` | image embed |
| `@icon(star)` | self-contained directive with arguments |
| `@icon(star, on: true)` | boolean argument |
| `@icon(star){body}` | **literal** — self-contained given a body |
| `@box{a {nested} b}` | directive — braces nest when balanced |
| `@box{unbalanced {` | **literal** — unbalanced brace |
| `- @box{x}` | list item containing a directive |
| `# @box{x}` | heading containing a directive |

---

## Checklist for generated documents

1. Blank line between blocks.
2. Space after every `#`, `-`, `*`, `+`, and `1.`.
3. Tables get outer pipes on every row, including the separator.
4. Close every ` ``` ` fence.
5. Escape a literal `$` before a number if you don't want math tested.
6. Use core syntax unless you know the host registered the extension or
   directive you want.
7. Keep directives on one line, and quote argument values containing spaces,
   commas, or colons.

## Status

Extensions ship in the engine today. **The directive seam is not upstream yet**
— it lives on `integration/directives` while it goes through review in
[#120](https://github.com/nodes-app/swift-markdown-engine/pull/120) and its
follow-ups. Treat the directive sections as accurate for that branch, and
check before relying on them elsewhere.
