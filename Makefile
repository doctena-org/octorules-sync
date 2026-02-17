#!/usr/bin/make -f

SHELL = /bin/bash

default: lint test

lint: lint-yaml lint-shell

lint-yaml:
	@echo "Linting YAML files..."
	@yamllint --no-warnings ./
	@echo "YAML lint passed."

lint-shell:
	@echo "Linting shell scripts..."
	@shellcheck ./scripts/*.sh
	@echo "Shell lint passed."

test:
	@echo "Running tests..."
	@bats tests/
	@echo "Tests passed."
