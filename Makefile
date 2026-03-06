# Makefile for nzi testing

.PHONY: test

test:
	@nvim --headless -i NONE --noplugin -u tests/init.lua \
		-c "lua require('plenary.test_harness').test_directory('tests/nzi', { progressive = true, halt_on_error = true })" \
		-c "qa!"
