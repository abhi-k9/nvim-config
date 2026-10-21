# Makefile for scoper.nvim — test, lint, format.
#
# Targets:
#   make test    — run plenary specs headlessly (clones plenary if absent)
#   make lint    — luacheck lua/, plugin/ and tests/
#   make check   — lint + fmt-check
#   make fmt-check — stylua --check (aligned blocks sit in
#                  `-- stylua: ignore start/end`; see the host Makefile)
#   make format  — stylua reformat in-place
#   make all     — lint + test
#
# Windows users without GNU make: see README "Testing" for the equivalent
# direct nvim command — it's literally one line.

NVIM      ?= nvim
LUACHECK  ?= luacheck
STYLUA    ?= stylua

.PHONY: test lint format fmt-check check all clean

all: lint test

test:
	$(NVIM) --headless --noplugin -u tests/minimal_init.lua \
		-c "PlenaryBustedDirectory tests/ { minimal_init = 'tests/minimal_init.lua' }"

lint:
	$(LUACHECK) lua/ plugin/ tests/

format:
	$(STYLUA) lua/ plugin/ tests/

fmt-check:
	$(STYLUA) --check lua/ plugin/ tests/

check: lint fmt-check

# --clean: no user config or plugins (they could install things, or print
# messages). The path never leaves nvim, so output can't corrupt it.
clean:
	$(NVIM) --clean --headless \
		-c "lua vim.fn.delete(vim.fn.stdpath('cache') .. '/test-deps', 'rf')" -c qa
