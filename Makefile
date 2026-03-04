# Makefile for nzi testing

TESTS_DIR = tests/nzi

.PHONY: test

test:
	@nvim --headless -i NONE --noplugin -u tests/init.lua \
		-c "lua require('plenary.test_harness').test_directory('$(TESTS_DIR)', { progressive = true, halt_on_error = true })" \
		-c "qa!"
