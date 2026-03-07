# Makefile for nzi testing

.PHONY: test

test:
	@NZI_MODEL_ALIAS=defaultModel nvim --headless --clean -u tests/init.lua \
		-c "lua require('plenary.test_harness').test_directory('tests/integration', { progressive = true, halt_on_error = true })" \
		-c "qa!"
	@NZI_MODEL_ALIAS=defaultModel nvim --headless --clean -u tests/init.lua \
		-c "lua require('plenary.test_harness').test_directory('tests/e2e', { progressive = true, halt_on_error = true })" \
		-c "qa!"
