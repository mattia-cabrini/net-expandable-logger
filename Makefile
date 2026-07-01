# Copyright (c) 2026 Mattia Cabrini
# SPDX-License-Identifier: MIT
#
# net-expandable-logger -- generic, self-configuring status logger.
# Usage:
#   make check       syntax-check all scripts
#   make install     interactively configure, install files and cron entry
#   make uninstall   remove files and cron entry

PREFIX ?= /usr/local

all:
	@echo "Targets: check, install, uninstall  (PREFIX=$(PREFIX))"

check:
	@sh install/check.sh

install:
	@sh install/install.sh "$(PREFIX)" "."

uninstall:
	@sh install/uninstall.sh "$(PREFIX)"

.PHONY: all check install uninstall
