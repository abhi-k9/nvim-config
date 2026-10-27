#!/usr/bin/env sh
# scripts/check-docs.sh
#
# Doc-sync guards: fail if the code and its documentation have drifted apart.
# Each guard checks both directions where the docs are a list of things the
# code defines, so a stale entry fails just like a missing one:
#
#   1. README Layout tree <-> files on disk: every file under lua/, tests/,
#      docs/, scripts/, .githooks/, .github/ and the repo root is drawn in
#      the tree (a directory drawn with no children covers its contents),
#      and every path the tree draws exists. scoper.nvim/ documents itself.
#   2. <leader> maps in lua/ <-> docs/cheatsheets/keymaps.html.
#   3. User commands (nvim_create_user_command, scoper's cmd()) are named in
#      README.md or a cheatsheet; :Scoper* commands are also listed in
#      scoper.nvim/README.md, and every :Scoper… the docs write exists.
#   4. Plugin specs in lua/plugins <-> lazy-lock.json, and every plugin row
#      in the README's "Notable extras" table is a spec.
#   5. Version floor: MIN_NVIM in init.lua == the README's "Neovim ≥ X" and
#      `nvim --version` notes == health.lua's fallback, and the CI matrix
#      tests nothing older.
#   6. Template pairs in docs/templates/cpp: .clang-tidy == clang-tidy.example
#      (comments aside); clangd.example's ClangTidy block == .clang-tidy's
#      checks and options; .clang-format and clang-format.example produce
#      the same `clang-format --dump-config` (skipped when clang-format 15+
#      isn't installed; set CLANG_FORMAT to point at a binary).
#   7. Every :checkhealth config section (each h.start in health.lua) is
#      named in the README's health description.
#   8. No README/cheatsheet text uses an API or command that was retired
#      (deprecated LSP log calls, auto-session's Session* commands, the npm
#      tree-sitter-cli).
#
# Pure POSIX sh plus grep/sed/awk/sort/comm/diff/find/mktemp — no Neovim
# boot — so it is fast enough to run both in CI (`make check-docs`) and in
# the pre-commit hook. Windows users without a shell get this gate from CI
# (or run it with Git for Windows' sh.exe).
#
# Exit status: 0 = in sync, 1 = drift found (details on stderr).

set -eu

# Run from the repo root regardless of how we were invoked. Neutralize CDPATH
# first (as its own assignment, so it can't redirect the cd) then move.
CDPATH=''
cd -- "$(dirname -- "$0")/.." || exit 1

errfile=$(mktemp)
tmp1=$(mktemp)
tmp2=$(mktemp)
tmp3=$(mktemp)
# shellcheck disable=SC2064  # expand paths now, on purpose
trap "rm -f '$errfile' '$tmp1' '$tmp2' '$tmp3'" EXIT INT TERM

skipped=""

# Append a problem. Writing to a FILE (not a shell var) so failures found
# inside a `while read` pipe subshell still survive to the end.
report() { printf 'check-docs: %s\n' "$1" >>"$errfile"; }

# Print each line of FILE1 that is not in FILE2 (both sorted).
only_in() { comm -23 "$1" "$2"; }

docs_files="README.md docs/cheatsheets/*.html"

# ── Guard 1: README Layout tree <-> files on disk ───────────────────────────
# Rebuild full paths from the box-drawn tree: each "│   " or "    " in front
# of a "├── "/"└── " marker is one level, and a name ending in "/" is a
# directory that later, deeper entries sit in.
awk '
  /^## Layout/ { inlayout = 1; next }
  inlayout && /^```/ { if (started) exit; started = 1; next }
  !started { next }
  {
    p = index($0, "├── ")
    if (!p) p = index($0, "└── ")
    if (!p) next
    prefix = substr($0, 1, p - 1)
    gsub(/│   /, "x", prefix)
    gsub(/    /, "x", prefix)
    depth = length(prefix)
    split(substr($0, p + length("├── ")), word, " ")
    path = ""
    for (i = 0; i < depth; i++) path = path dir[i]
    if (word[1] ~ /\/$/) dir[depth] = word[1]
    print path word[1]
  }' README.md >"$tmp1"

# Byproducts of running things here (Python bytecode, editor swap files,
# Finder metadata) are not part of the layout.
{
  find lua tests docs scripts .githooks .github -name __pycache__ -prune -o -type f \
    ! -name '*.pyc' ! -name '*.sw?' ! -name '*~' ! -name '.DS_Store' -print 2>/dev/null
  for f in * .[!.]*; do
    [ -f "$f" ] || continue
    case "$f" in *.sw? | *~ | .DS_Store | local.lua) continue ;; esac
    printf '%s\n' "$f"
  done
} | sort -u >"$tmp2"

awk -v files="$tmp2" '
  { n++; entry[n] = $0; listed[$0] = 1 }
  END {
    for (i = 1; i <= n; i++) {
      if (entry[i] !~ /\/$/) continue
      kids = 0
      for (j = 1; j <= n; j++)
        if (j != i && index(entry[j], entry[i]) == 1) { kids = 1; break }
      if (!kids) collapsed[entry[i]] = 1
    }
    while ((getline f < files) > 0) {
      if (f in listed) continue
      covered = 0
      for (d in collapsed) if (index(f, d) == 1) { covered = 1; break }
      if (!covered) print f
    }
  }' "$tmp1" | while IFS= read -r f; do
  report "README layout tree is missing: $f"
done

while IFS= read -r p; do
  [ -e "$p" ] || report "README layout tree lists a path that doesn't exist: $p"
done <"$tmp1"

# ── Guard 2: <leader> maps in source <-> keymaps.html ───────────────────────
# Strip whole-line comments first so prose that mentions a mapping (e.g. a
# doc comment referencing <leader>lr) is not mistaken for a binding. Only
# alphabetic suffixes are compared: numeric jumps (<leader>1..9) are
# documented as a single "1…9" range, so listing them literally would
# false-fail.
find lua -type f -name '*.lua' -exec grep -hvE '^[[:space:]]*--' {} + 2>/dev/null \
  | grep -oE '<leader>[A-Za-z]+' | sort -u >"$tmp2" || :
grep -oE '(&lt;leader&gt;|<leader>)[A-Za-z]+' docs/cheatsheets/keymaps.html 2>/dev/null \
  | sed 's/&lt;/</g; s/&gt;/>/g' | sort -u >"$tmp3" || :
only_in "$tmp2" "$tmp3" | while IFS= read -r m; do
  report "leader map in source but not in keymaps.html: $m"
done
only_in "$tmp3" "$tmp2" | while IFS= read -r m; do
  report "leader map in keymaps.html but not in source: $m"
done

# ── Guard 3: user commands <-> docs ─────────────────────────────────────────
find init.lua lua scoper.nvim/plugin -type f -name '*.lua' \
  -exec grep -hoE '(nvim_create_user_command|^cmd)\("[A-Z][A-Za-z0-9]*"' {} + 2>/dev/null \
  | sed 's/.*("//; s/"$//' | sort -u >"$tmp1" || :
while IFS= read -r c; do
  # shellcheck disable=SC2086  # docs_files is a glob list on purpose
  grep -qwF -- "$c" $docs_files ||
    report "user command :$c is not named in README.md or docs/cheatsheets/"
  case "$c" in
    Scoper*)
      grep -qwF -- "$c" scoper.nvim/README.md ||
        report "user command :$c is not listed in scoper.nvim/README.md" ;;
  esac
done <"$tmp1"
# shellcheck disable=SC2086
grep -ohE ':Scoper[A-Z][A-Za-z]*' $docs_files scoper.nvim/README.md 2>/dev/null \
  | sed 's/^://' | sort -u >"$tmp2" || :
only_in "$tmp2" "$tmp1" | while IFS= read -r c; do
  report "docs name :$c, but scoper.nvim/plugin defines no such command"
done

# ── Guard 4: plugin specs <-> lazy-lock.json ────────────────────────────────
# A spec string is an "owner/repo" literal that opens a line or a table, or
# follows `dependencies =` or a comma. lazy.nvim locks it under the repo
# name, or under `name = "…"` when that is the very next line.
find lua/plugins -type f -name '*.lua' -exec cat {} + 2>/dev/null \
  | grep -vE '^[[:space:]]*--' | awk '
    pending != "" && /^[[:space:]]*name[[:space:]]*=[[:space:]]*"/ {
      v = $0; sub(/^[^"]*"/, "", v); sub(/".*/, "", v); lock[pending] = v
    }
    { pending = "" }
    {
      line = $0; first = 1
      while (match(line, /(^[[:space:]]*\{?[[:space:]]*|dependencies[[:space:]]*=[[:space:]]*\{?[[:space:]]*|,[[:space:]]*)"[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+"/)) {
        s = substr(line, RSTART, RLENGTH)
        line = substr(line, RSTART + RLENGTH)
        sub(/^[^"]*"/, "", s); sub(/"$/, "", s)
        if (!(s in lock)) { r = s; sub(/.*\//, "", r); lock[s] = r }
        if (first && s ~ /./) pending = s
        first = 0
      }
    }
    END { for (s in lock) print lock[s] }' | sort -u >"$tmp1"
grep -oE '^[[:space:]]*"[^"]+":' lazy-lock.json 2>/dev/null \
  | sed 's/^[[:space:]]*"//; s/":$//' | grep -vx 'lazy.nvim' | sort -u >"$tmp2" || :
only_in "$tmp1" "$tmp2" | while IFS= read -r p; do
  report "plugin $p has a spec in lua/plugins but no lazy-lock.json entry"
done
only_in "$tmp2" "$tmp1" | while IFS= read -r p; do
  report "lazy-lock.json pins $p, but no spec in lua/plugins installs it"
done
bt=$(printf '\140') # a backtick, kept out of quoted patterns
grep -oE "^\| ${bt}[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+${bt}" README.md 2>/dev/null \
  | sed "s/^| ${bt}//; s/${bt}\$//" | while IFS= read -r s; do
    find lua/plugins -type f -name '*.lua' -exec grep -qF -- "\"$s\"" {} + ||
      report "README plugin table lists $s, but no spec in lua/plugins uses it"
  done

# ── Guard 5: one Neovim version floor everywhere ────────────────────────────
min=$(sed -n 's/^local MIN_NVIM = "\([0-9.]*\)".*/\1/p' init.lua)
if [ -z "$min" ]; then
  report 'init.lua has no  local MIN_NVIM = "x.y.z"  line'
else
  grep -qF "Neovim ≥ $min" README.md ||
    report "README.md doesn't state the floor as \"Neovim ≥ $min\" (MIN_NVIM in init.lua)"
  grep -oE 'Neovim ≥ [0-9]+\.[0-9]+(\.[0-9]+)?|nvim --version[^0-9]*[0-9]+\.[0-9]+(\.[0-9]+)?' README.md \
    | sed 's/.*[^0-9.]//' | sort -u | while IFS= read -r v; do
      [ "$v" = "$min" ] || report "README.md gives the Neovim floor as $v; MIN_NVIM in init.lua is $min"
    done
  grep -oE 'config_min_nvim or "[0-9.]+"' lua/config/health.lua 2>/dev/null \
    | sed 's/.*"\([0-9.]*\)"/\1/' | while IFS= read -r v; do
      [ "$v" = "$min" ] || report "health.lua falls back to Neovim $v; MIN_NVIM in init.lua is $min"
    done
  grep -E '^[[:space:]]*nvim:' .github/workflows/ci.yml 2>/dev/null \
    | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | sed 's/^v//' | while IFS= read -r v; do
      older=$(awk -v a="$v" -v b="$min" 'BEGIN {
        split(a, x, "."); split(b, y, ".")
        for (i = 1; i <= 3; i++) if (x[i] + 0 != y[i] + 0) { print (x[i] + 0 < y[i] + 0); exit }
        print 0 }')
      [ "$older" = 0 ] || report "ci.yml tests Neovim v$v, older than MIN_NVIM $min"
    done
fi

# ── Guard 6: C++ template pairs ─────────────────────────────────────────────
ct_dir=docs/templates/cpp

# 6a. .clang-tidy and clang-tidy.example carry identical settings.
if [ -f "$ct_dir/.clang-tidy" ] && [ -f "$ct_dir/clang-tidy.example" ]; then
  # Compare with comments and blank lines removed and trailing space trimmed.
  strip() { grep -vE '^[[:space:]]*#' "$1" | grep -vE '^[[:space:]]*$' | sed 's/[[:space:]]*$//'; }
  strip "$ct_dir/.clang-tidy" >"$tmp1"
  strip "$ct_dir/clang-tidy.example" >"$tmp2"
  if ! diff -q "$tmp1" "$tmp2" >/dev/null 2>&1; then
    report ".clang-tidy and clang-tidy.example settings differ (compare them with comments stripped)"
  fi
else
  report "expected both $ct_dir/.clang-tidy and $ct_dir/clang-tidy.example to exist"
fi

# 6b. clangd.example's Diagnostics.ClangTidy block == .clang-tidy. Both are
# reduced to "add <check>", "remove <check>" and "option <key>: <value>"
# lines (quotes dropped), then compared.
if [ -f "$ct_dir/.clang-tidy" ] && [ -f "$ct_dir/clangd.example" ]; then
  grep -vE '^[[:space:]]*#' "$ct_dir/.clang-tidy" | awk '
    /^[^[:space:]]/ { sec = "" }
    /^Checks:/ { sec = "checks"; next }
    /^CheckOptions:/ { sec = "opts"; next }
    sec == "checks" {
      n = split($0, t, ",")
      for (i = 1; i <= n; i++) {
        c = t[i]; gsub(/[[:space:]]/, "", c)
        if (c == "" || c == "-*") continue
        if (c ~ /^-/) print "remove " substr(c, 2); else print "add " c
      }
    }
    sec == "opts" && /:/ {
      line = $0; gsub(/[[:space:]'\''"]/, "", line); sub(/:/, ": ", line)
      print "option " line
    }' | sort >"$tmp1"
  grep -vE '^[[:space:]]*#' "$ct_dir/clangd.example" | sed 's/[[:space:]]#.*//' | awk '
    /^[^[:space:]]/ { indiag = ($0 ~ /^Diagnostics:/); intidy = 0; next }
    indiag && /^  [^[:space:]]/ { intidy = ($0 ~ /^  ClangTidy:/); sec = ""; next }
    !intidy { next }
    /^    Add:/ { sec = "add"; next }
    /^    Remove:/ { sec = "remove"; next }
    /^    CheckOptions:/ { sec = "option"; next }
    /^    [^[:space:]]/ { sec = ""; next }
    (sec == "add" || sec == "remove") && /^      - / {
      c = $0; sub(/^      - /, "", c); gsub(/[[:space:]]/, "", c); print sec " " c
    }
    sec == "option" && /:/ {
      line = $0; gsub(/[[:space:]'\''"]/, "", line); sub(/:/, ": ", line)
      print "option " line
    }' | sort >"$tmp2"
  if ! diff -q "$tmp1" "$tmp2" >/dev/null 2>&1; then
    diff "$tmp1" "$tmp2" | grep -E '^[<>]' | sed 's/^</only in .clang-tidy:/; s/^>/only in clangd.example:/' \
      | while IFS= read -r d; do report "clangd.example ClangTidy block vs .clang-tidy: $d"; done
  fi
fi

# 6c. .clang-format and clang-format.example produce the same style.
cf=${CLANG_FORMAT:-clang-format}
if command -v "$cf" >/dev/null 2>&1; then
  major=$("$cf" --version 2>/dev/null | sed -n 's/.*version \([0-9][0-9]*\).*/\1/p')
  if [ "${major:-0}" -ge 15 ]; then
    if "$cf" --style="file:$ct_dir/.clang-format" --dump-config >"$tmp1" 2>/dev/null &&
      "$cf" --style="file:$ct_dir/clang-format.example" --dump-config >"$tmp2" 2>/dev/null; then
      diff "$tmp1" "$tmp2" | grep -E '^[<>]' | sed 's/^</.clang-format:/; s/^>/clang-format.example:/' \
        | while IFS= read -r d; do report "clang-format --dump-config differs: $d"; done
    else
      report "clang-format $major couldn't read $ct_dir/.clang-format or clang-format.example"
    fi
  else
    skipped="$skipped clang-format-pair(needs clang-format 15+)"
  fi
else
  skipped="$skipped clang-format-pair(no clang-format)"
fi

# ── Guard 7: every health.lua section is named in the README health block ───
# Each `h.start("Title")` in health.lua is a section the user sees when they
# run :checkhealth config; the README's health description must name it, so a
# new section can't be added without documenting it. Match the title's stable
# part (before any " (...)" qualifier) as a fixed substring of the README
# bullet, collapsed to one line so a title wrapped across lines still matches.
if [ -f lua/config/health.lua ] && [ -f README.md ]; then
  block=$(sed -n '/checkhealth config/,/Implemented in/p' README.md | tr '\n' ' ' | tr -s ' ')
  grep -oE 'h\.start\("[^"]*"\)' lua/config/health.lua \
    | sed -E 's/h\.start\("(.*)"\)/\1/' | while IFS= read -r title; do
      core=${title%% (*} # drop a trailing " (...)" qualifier
      case "$block" in
        *"$core"*) : ;;
        *) report "health.lua section not named in README health block: $core" ;;
      esac
    done
fi

# ── Guard 8: no retired APIs or commands in the docs ────────────────────────
retired='vim\.lsp\.set_log_level|vim\.lsp\.get_log_path|npm (install|i) (-g|--global) tree-sitter-cli|:Session(Save|Restore|Delete|Search|Toggle|PurgeOrphaned)([^A-Za-z]|$)'
# shellcheck disable=SC2086
grep -nE "$retired" $docs_files 2>/dev/null | cut -d: -f1-2 | while IFS= read -r hit; do
  report "retired API/command in the docs at $hit"
done

# ── Verdict ─────────────────────────────────────────────────────────────────
[ -z "$skipped" ] || echo "check-docs: skipped:$skipped"
if [ -s "$errfile" ]; then
  echo "check-docs: documentation is out of sync with the code:" >&2
  sort -u "$errfile" >&2
  echo "check-docs: fix the above (or update the docs) and re-run." >&2
  exit 1
fi
echo "check-docs: docs in sync (layout tree, keymaps, commands, plugins, version floor, templates, health, retired APIs)."
exit 0
