; Fold queries for Lex
; See: https://neovim.io/doc/user/treesitter.html#_treesitter-folding
;
; Enables tree-sitter-based folding (foldmethod=expr) for Lex documents.
; Fold targets are structural blocks that benefit from collapsing.

(session) @fold
(verbatim_block) @fold
(definition) @fold
(annotation_block) @fold
(list) @fold
