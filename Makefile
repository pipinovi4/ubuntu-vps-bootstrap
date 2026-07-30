SHELL := /usr/bin/env bash

.PHONY: setup-dev lint format format-check test integration-test check

setup-dev:
	sudo apt-get update
	sudo apt-get install -y shellcheck shfmt bats

lint:
	shellcheck bootstrap.sh deploy.sh uninstall.sh lib/*.sh tests/integration/*.sh

format:
	shfmt -w -i 2 -ci bootstrap.sh deploy.sh uninstall.sh lib/*.sh tests/integration/*.sh

format-check:
	shfmt -d -i 2 -ci bootstrap.sh deploy.sh uninstall.sh lib/*.sh tests/integration/*.sh

test:
	bats tests/unit

integration-test:
	./tests/integration/container-smoke.sh

check: lint format-check test
