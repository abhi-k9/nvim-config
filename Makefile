# Makefile — convenience runner for tests and linting.
#
# Targets:
#   make test        — run the config's plenary specs (tests/*_spec.lua)
#   make lint        — luacheck init.lua lua/ tests/
#   make check       — luacheck + stylua --check, here AND in scoper.nvim/
#                      (its lua/, plugin/ and tests/)
#   make check-docs  — verify the docs still match the code (scripts/check-docs.sh
#                      lists the guards) — no Neovim needed
#   make format      — stylua reformat both trees in place
#   make all         — check + check-docs + test
#   make test-scoper — `make test` inside scoper.nvim/
#   make test-seed   — Python tests for scripts/offline-seed.py
#   make check-actions — offline immutable CI pin guard and updater tests
#   make ci          — what CI runs: check + check-docs + check-actions + test + test-scoper
#                      + test-seed
#   make hooks       — enable the tracked git pre-commit hook (.githooks/)
#
# FORMATTING: the tree is stylua-clean and `check` enforces it
# (`stylua --check`). Hand-aligned blocks — option lists, keymap tables,
# icon maps — are wrapped in `-- stylua: ignore start` / `-- stylua:
# ignore end`, so formatting leaves their columns alone. Put new aligned
# tables inside such a pair; everything else is plain stylua.
# (Inside a TABLE, stylua still re-spaces trailing comments even in an
# ignore range; only `key   = value` alignment survives there.)
#
# Windows users without GNU make can run the underlying nvim command
# directly; see README "Testing" for one-liners.

NVIM      ?= nvim
LUACHECK  ?= luacheck
STYLUA    ?= stylua
PYTHON    ?= python3

.PHONY: test test-scoper test-seed lint format fmt-check check check-docs check-actions all ci hooks

all: check check-docs test

# Everything the CI workflow (.github/workflows/ci.yml) gates on, in one
# local command: static analysis over both trees, doc-sync/action-pin guards,
# both spec suites and the offline-seed tests. CI also runs native platform
# jobs (including the Windows adapter fixture) that this command cannot replace.
ci: check check-docs check-actions test test-scoper test-seed

check-actions:
	$(PYTHON) scripts/update-ci-actions.py --check
	PYTHONDONTWRITEBYTECODE=1 $(PYTHON) -m unittest discover -s tests -p "ci_actions_test.py"

# Point git at the version-controlled hook directory so .githooks/pre-commit
# runs on every commit (luacheck + stylua over the staged Lua, plus the
# doc-sync guards). One-time per clone; safe to re-run. Undo with
# `git config --unset core.hooksPath`.
hooks:
	git config core.hooksPath .githooks
	@echo "pre-commit hook enabled (core.hooksPath = .githooks)"

test:
	$(NVIM) --headless --noplugin -u NONE -l scoper.nvim/tests/run.lua

test-scoper:
	$(MAKE) -C scoper.nvim test

# scripts/offline-seed.py against hostile seeds and a fake nvim; no network.
test-seed:
	PYTHONDONTWRITEBYTECODE=1 $(PYTHON) -m unittest discover -s tests -p "offline_seed_test.py"

lint:
	$(LUACHECK) init.lua lua/ tests/

format:
	$(STYLUA) init.lua lua/ tests/
	$(MAKE) -C scoper.nvim format

fmt-check:
	$(STYLUA) --check init.lua lua/ tests/

# Fail if the docs have drifted from the code (README tree, keymaps, user
# commands, plugin list, version floor, template pairs; see the script
# header). Pure POSIX shell, no Neovim — the same gate the pre-commit hook runs.
check-docs:
	sh scripts/check-docs.sh

check: lint fmt-check
	$(MAKE) -C scoper.nvim lint fmt-check
