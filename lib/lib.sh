# Copyright (c) 2026 Mattia Cabrini
# SPDX-License-Identifier: MIT
#
# lib.sh -- shared helpers for net-expandable-logger collectors. nel-run sources
# this once, then runs each collector as ( . collectors/<name> ), so every
# collector can call these functions.
#
# A collector writes, into the current work directory, for its tag X:
#   log.X.html            body fragment (HTML)
#   attachment.X.html     attachment list fragment (may be empty)
#   attachment.X.Y.dat    attachment payload; Y is the final name WITH extension
#   X.sem                 semaphore, created LAST by seal()
# X must contain no dot (the assembler splits fragment names on dots).
#
# The date helpers work on both FreeBSD (BSD date) and Linux (GNU date).

# esc -- HTML-escape stdin so log output can't break the page or inject markup.
esc() {
	sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'
}

# have CMD -- true if CMD exists on PATH. Used to guard optional tools.
have() {
	command -v "$1" >/dev/null 2>&1
}

# day_label N -- the syslog-style "%b %e" date (e.g. "Jul  1") for N days ago,
# in the C locale so month names are English. Tries BSD "date -v" first, then
# falls back to GNU "date -d".
day_label() {
	if date -v-"$1"d '+%b %e' >/dev/null 2>&1; then
		LC_ALL=C date -v-"$1"d '+%b %e'
	else
		LC_ALL=C date -d "-$1 days" '+%b %e'
	fi
}

# since_ere D -- build an extended regex that matches the syslog date label of
# any of the last D+1 days (today, yesterday, ... D days ago). Collectors use it
# as  grep -E "^$(since_ere 2)"  to keep only the last ~48h of a log.
#
# "%e" pads single-digit days with a space ("Jul  1" vs "Jul 15"), so we replace
# every run of spaces with " +" in the regex; that way one or two spaces match.
since_ere() {
	days=$1
	pattern=""

	day=0
	while [ "$day" -le "$days" ]; do
		label=$(day_label "$day" | sed 's/  */ +/g')
		if [ -z "$pattern" ]; then
			pattern="$label"
		else
			pattern="$pattern|$label"
		fi
		day=$((day + 1))
	done

	printf '(%s)' "$pattern"
}

# attach Y -- store stdin as the attachment payload named Y (name.ext).
attach() {
	cat > "attachment.$TAG.$1.dat"
}

# seal -- plant the semaphore that marks this collector as "done and reporting".
# MUST be the last thing a collector does: nel-run/compress/assemble only look
# at collectors that have sealed.
seal() {
	: > "$TAG.sem"
}
