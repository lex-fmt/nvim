; Highlight queries for Lex
; See: https://tree-sitter.github.io/tree-sitter/syntax-highlighting
;
; These captures map tree-sitter CST nodes to TextMate scopes. The LSP's
; semantic tokens override these in editors, but the scopes here must be
; structurally correct — a session title is a heading, a list item is a
; list item, a definition subject is a definition term.
;
; Reference: lex-analysis/src/semantic_tokens.rs defines the authoritative
; LSP token types. This file mirrors that mapping at CST granularity.
;
; PRECEDENCE: In tree-sitter queries, LATER patterns override earlier ones
; when multiple patterns match the same node. Specific overrides (e.g.
; verbatim closing markers) must appear AFTER their generic counterparts.

; === Document Title ===
; Document title is the primary heading (LSP: DocumentTitle)
(document_title
  title: (line_content) @markup.heading)

; Document subtitle (LSP: DocumentSubtitle)
(document_subtitle
  subtitle: (line_content) @markup.heading.subtitle)

; Document title sequence marker (e.g., numbered title)
(document_title
  title: (line_content
    (list_marker) @punctuation.definition.heading))

; === Sessions ===
; Session titles are headings (LSP: SessionTitleText)
(session
  title: (line_content) @markup.heading)

; Session sequence marker (LSP: SessionMarker) — numbered titles like "1. Title"
; list_marker inside a session title is structural, not a list item
(session
  title: (line_content
    (list_marker) @punctuation.definition.heading))

; === Definitions ===
; Definition subjects are terms being defined (LSP: DefinitionSubject)
; NOT headings — they are variable/term definitions
(definition
  subject: (subject_content) @variable.other.definition)

; === Verbatim Blocks ===
; Verbatim subject line (LSP: VerbatimSubject)
(verbatim_block
  subject: (subject_content) @markup.raw.block)

; Verbatim block body content is raw/preformatted (LSP: VerbatimContent)
(verbatim_block
  (paragraph) @markup.raw)
(verbatim_block
  (definition) @markup.raw)
(verbatim_block
  (list) @markup.raw)
(verbatim_block
  (verbatim_content) @markup.raw)
(verbatim_block
  (session) @markup.raw)

; Verbatim group item subjects and content
(verbatim_group_item
  subject: (subject_content) @markup.raw.block)
(verbatim_group_item
  (paragraph) @markup.raw)
(verbatim_group_item
  (definition) @markup.raw)
(verbatim_group_item
  (list) @markup.raw)
(verbatim_group_item
  (verbatim_content) @markup.raw)
(verbatim_group_item
  (session) @markup.raw)

; === Lists ===
; List marker (- , 1. , a) , etc.) — captures just the marker portion
; (LSP: ListMarker). Content is handled by inline captures below.
(list_item
  (list_marker) @markup.list)

; === Annotations (generic) ===
; Annotation delimiters (LSP: part of AnnotationLabel)
(annotation_marker) @punctuation.special
(annotation_close) @punctuation.special

; Annotation header — the label between :: markers (LSP: AnnotationLabel)
(annotation_header) @comment

; Annotation inline text (LSP: AnnotationContent)
(annotation_inline_text) @comment

; Annotation block body content (LSP: AnnotationContent)
(annotation_block
  (_) @comment)

; === Verbatim closing metadata (overrides generic annotation captures) ===
; Annotation nodes inside verbatim_block are the closing `:: label ::` line
; (LSP: VerbatimLanguage/VerbatimAttribute). These MUST appear AFTER generic
; annotation captures so they take priority.
(verbatim_block
  (annotation_marker) @markup.raw.block)
(verbatim_block
  (annotation_close) @markup.raw.block)
(verbatim_block
  (annotation_header) @markup.raw.block)

; === Table structure ===
; Tables are definitions whose body contains table_row nodes. The CST
; preserves the full hierarchy: definition > table_row > table_cell >
; text_content — tables are NOT terminal nodes. Cell block content
; (lists, definitions, etc.) is resolved at the AST level by lex-core.

; Table caption — italic to distinguish from regular definitions.
; Overrides the generic @variable.other.definition capture above.
(definition
  subject: (subject_content) @markup.italic
  (table_row))

; Header row — first table_row in a definition (bold text).
; The anchor (.) ensures only the first row after the subject matches.
(definition
  subject: (_) .
  (table_row
    (table_cell
      (text_content) @markup.bold)))

; Pipe delimiters — dimmed punctuation
(table_row
  (pipe_delimiter) @comment)

; Table separator rows — fully dimmed (cosmetic, parser ignores them)
(table_separator_row) @comment

; Table cell inline content inherits from the inline rules below.
; Merge markers (>> and ^^) are highlighted via content predicates:
((table_cell
  (text_content) @keyword.operator)
 (#match? @keyword.operator "^\\s*>>\\s*$"))
((table_cell
  (text_content) @keyword.operator)
 (#match? @keyword.operator "^\\s*\\^\\^\\s*$"))

; === Inline formatting ===
(strong) @markup.bold
(emphasis) @markup.italic
(code_span) @markup.raw.inline
(math_span) @markup.math
(escape_sequence) @string.escape

; === References (typed) ===
; Generic fallback — all references are links
(reference) @markup.link

; Specific reference type overrides (later = higher priority)
(citation_reference) @markup.link
(annotation_reference) @markup.link
(url_reference) @markup.link.url
(file_reference) @markup.link.url
(session_reference) @markup.link
(tocome_reference) @constant.builtin
(number_reference) @markup.link

; === Spell checking ===
; Enable spell checking on prose content (leaf text nodes)
(line_content) @spell
(text_content) @spell
(subject_content) @spell

; Disable in verbatim blocks (content is code/preformatted)
(verbatim_block (paragraph (text_line (line_content) @nospell)))
(verbatim_block (verbatim_content) @nospell)
(verbatim_block subject: (subject_content) @nospell)
(verbatim_group_item (paragraph (text_line (line_content) @nospell)))
(verbatim_group_item (verbatim_content) @nospell)
(verbatim_group_item subject: (subject_content) @nospell)

; Disable on non-prose inline elements
(code_span) @nospell
(math_span) @nospell
(escape_sequence) @nospell

; Disable on metadata/annotations
(annotation_header) @nospell
(annotation_inline_text) @nospell
