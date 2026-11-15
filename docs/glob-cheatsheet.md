# Glob cheatsheet

Globs select **paths**. Regex searches **text** in Grug-Far's Search field
(ripgrep engine). Use forward slashes in glob patterns, including on Windows.

## Common patterns

| Pattern | Matches |
| --- | --- |
| `src/*.cpp` | `.cpp` files directly inside `src` |
| `src/**/*.cpp` | `.cpp` files in `src` and any subdirectory |
| `**/*.cpp` | `.cpp` files at any depth, including the project root |
| `**/*.{cpp,hpp}` | C++ source or header files at any depth |
| `**/test_*.cpp` | Files such as `test_parser.cpp` |
| `**/part?.cpp` | One character after `part`, such as `part1.cpp` |
| `**/part[0-9].cpp` | One digit after `part` |
| `**/{build,vendor}/**` | Contents of directories named `build` or `vendor` |

`*` matches within one path component; `**/` crosses zero or more directories.
`?` matches one character; `[abc]` matches one listed character; `{a,b}` selects
alternatives. A dot is literal: use `*.cpp`, not the regex `.*\.cpp$`.

## Scoper

```vim
:ScoperAdd **/*.{cpp,hpp}
:ScoperExclude **/{build,vendor}/**
:ScoperShow
:ScoperStatus
```

Use `:ScoperToggle` if status is OFF, then `:ScoperFind` or `:ScoperGrep`.
`ScoperAdd` adds to existing includes; `ScoperClear` clears includes but keeps
excludes. Ordinary directories such as `src/` include their descendants.

- Empty includes mean everything, with exclusions still applied.
- Exclusions always win; disabled Scoper ignores both lists.
- Use `ScoperExclude pattern`, not `ScoperAdd !pattern`. Scoper does not use
  leading `!` to negate an include.
- `ScoperAdd` accepts multiple space-separated entries. Escape spaces in an
  include: `:ScoperAdd my\ dir/**/*.cpp`. `ScoperExclude` takes its entire
  argument as one pattern: `:ScoperExclude **/my dir/**`.
- Prefer `**/*.cpp` for includes at every depth. A slashless **exclude**, such
  as `*.o` or `build`, matches path components at any depth.
- Path suggestions stop once you type glob syntax, avoiding recursive
  completion scans. Enter still adds the pattern.

## Grug-Far (ripgrep engine)

Use **Paths** for starting files/directories, **Files Filter** for globs (one
per line), and **Search** for the text regex. For example:

```text
Search:       old_name
Replacement:  new_name
Paths:        src
Files Filter:
**/*.{cpp,hpp}
!**/generated/**
```

In Files Filter, leading `!` excludes matches. Put exclusions after inclusions:
ripgrep uses the last matching glob, unlike Scoper's unconditional exclusion
precedence. Do not surround Files Filter patterns with shell quotes; spaces
within a line are part of the pattern. Flags can also contain `--glob` options.

Scoper's active scope is not automatically applied to ordinary Grug-Far searches.
Inspect the result list before replacing. See [search configuration](search-session-configuration.md)
for scope and replacement boundaries.
