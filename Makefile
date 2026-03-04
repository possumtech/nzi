# Makefile for nzi testing

TESTS_DIR = tests/nzi

.PHONY: test

test:
	@nvim --headless --noplugin -u tests/init.lua \
		-c "PlenaryBustedDirectory $(TESTS_DIR) { progressive = true }"
