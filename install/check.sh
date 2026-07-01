#!/bin/sh
# Copyright (c) 2026 Mattia Cabrini
# SPDX-License-Identifier: MIT
#
# check.sh -- syntax-check every shell script in the repo with "sh -n" (parse
# only, run nothing). Prints OK/FAIL per file and exits non-zero if any failed.
# Invoked by `make check`.

set -u
rc=0

for f in bin/nel-run bin/nel-compress bin/nel-assemble lib/lib.sh \
         collectors/* install/install.sh install/uninstall.sh; do
	if sh -n "$f" 2>/dev/null; then
		echo "OK   $f"
	else
		echo "FAIL $f"
		rc=1
	fi
done

exit $rc
