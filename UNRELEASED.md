<!-- Release notes for the next version. -->
<!-- Updated as work is done; consumed by scripts/create-release. -->

- Strengthened the tree-sitter injection test to assert all five fixture
  languages (python, javascript, json, rust, bash), validate that
  `@injection.content` ranges are non-empty and inside the buffer, and
  reject any injection produced for plain (un-annotated) verbatim blocks.
- Fixed a stale `M.version` constant that had drifted from the released
  tag, and taught `scripts/create-release` to bump it automatically.
