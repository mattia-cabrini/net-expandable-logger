# net-expandable-logger

Copyright (c) 2026 Mattia Cabrini
SPDX-License-Identifier: MIT

A small, generic, self-configuring status logger for FreeBSD. It runs a set of
collectors, assembles their output into a single `.noeml` message, and drops it
into a deposit directory.

These scripts do not deliver these e-mails. Delivery should be handled by
[SimpleQueueMailing](https://github.com/mattia-cabrini/SimpleQueueMailing).

## Install

```
git clone <repo> net-expandable-logger
cd net-expandable-logger
make check        # optional: syntax-check everything
sudo make install # interactive: asks recipient, deposit dir, firewall, cron time
```

`make install` asks the few choices that matter:

- Host label;
- Recipient;
- Deposit and work directories;
- Log sources;
- Firewall (auto-detected);
- Optional PGP signing key; and
- The daily time to run.

The configuration is written into `/usr/local/etc/nel.conf`.

Scripts are written into `/usr/local/libexec/nel`

Execution is scheduled in `/etc/crontab` using the chosen time.

```
sudo make uninstall   # removes files and the cron entry; keeps the spool
```

## Requirements

- FreeBSD with a POSIX `/bin/sh`.
- [`cmc-eml`](https://github.com/mattia-cabrini/cmc-eml) in `PATH` (builds the MIME message).
- `tcpdump` if you use pf and want firewall events from `pflog`.
- `gpg` only if you configure a signing key.

## What it collects

Six collectors ship in `collectors/`, and adding one is just dropping a seventh
script there:

- **df** — filesystem usage, in the e-mail body only.
- **syslog** — the whole system log of the last 48h, attached.
- **syslog_no_fw** — the same log with firewall lines removed, attached.
- **fw_log** — firewall events of the last 48h, attached (pf via `pflog`,
  ipfw via `/var/log/security`).
- **fw_status** — the firewall state as-is, in the body only (pf: info, NAT and
  numbered ruleset; ipfw: numbered ruleset with counters).
- **access** — SSH logins and failures of the last 48h, attached.

## How it works

`nel-run` (from cron) works in `$WORK`: it runs every collector, gzips
attachments above `GZIP_THRESHOLD`, then `nel-assemble` builds one `.noeml`
(hashing each attachment with SHA-256) and drops it atomically into `$DEPOSIT`
via a `.part` temporary that is then renamed. Delivery of that `.noeml` is left
to your mail pipeline.

Collectors are sourced, not executed, so each writes fragments (`log.X.html`,
`attachment.X.html`, `attachment.X.Y.dat`, and a final `X.sem` semaphore) into
the work directory; the tag `X` must contain no dot.

## How to Write a Collector

A collector is a POSIX `/bin/sh` script dropped into `collectors/`. On install
it is copied to `$SVCDIR` (`/usr/local/libexec/nel/collectors`) and, on every
run, `nel-run` **sources** it in a subshell whose working directory is `$WORK`:

```
( . collectors/<name> )
```

Because it is sourced, not executed, a shebang is decorative and there is no
argument passing — the collector communicates only by writing files. Because it
runs in a subshell, an `exit` aborts just that collector, and the variables it
sets never leak into the next one.

### What is already in scope

- **Every `nel.conf` variable**, so a collector can read `HOSTLABEL`,
  `FIREWALL`, `MESSAGES_FILE`, `AUTH_FILE`, `WORK`, and so on.
- **The helpers from `lib.sh`**, already sourced by `nel-run`:
  - `esc` — HTML-escapes stdin (`&`, `<`, `>`); pipe any untrusted text through
    it, especially inside `<pre>`.
  - `have CMD` — true if `CMD` is on `PATH`; guard optional tools with it.
  - `since_ere D` — an ERE alternation matching the syslog date labels of today
    through `D` days ago, for `grep -E "^$(since_ere 2)"` "last 48h" filters.
  - `day_label N` — the syslog `"%b %e"` label for `N` days ago.
  - `attach Y` — write stdin as the attachment payload named `Y` (name with
    extension); shorthand for `cat > attachment.$TAG.$Y.dat`.
  - `seal` — plant the `$TAG.sem` semaphore. **Call it last, always.**

### The output contract

Pick a `TAG` first: a short identifier with **no dot** (the assembler splits
fragment names on dots). It must be unique across collectors, or two collectors
will clobber each other's fragments. Then write, into the current directory:

| File | Meaning |
|------|---------|
| `log.$TAG.html`        | HTML fragment shown in the e-mail **body**. |
| `attachment.$TAG.html` | HTML `<li>` list describing your attachments; write it **empty** if you have none. |
| `attachment.$TAG.$Y.dat` | An attachment payload. `$Y` is its final filename **with extension** (e.g. `syslog.txt`). Use `attach`. |
| `$TAG.sem`             | The semaphore, created **last** by `seal`. |

The semaphore is the trigger: `nel-compress` and `nel-assemble` iterate over
`*.sem`, so a collector that never seals is silently ignored — this is exactly
how you say "nothing to report" (see `syslog` exiting when its source is
unreadable). Everything you produce before `seal` is only picked up once the
semaphore lands, so seal only when the fragments are complete.

The extension of `$Y` drives the MIME type in the message (`.txt`/`.log` →
`text/plain`, `.csv`, `.json`, `.xml`, `.gz`, everything else
`application/octet-stream`). Attachments larger than `GZIP_THRESHOLD` are
gzipped automatically (`.dat` → `.dat.gz`) and every attachment is hashed with
SHA-256 — you do not handle compression or hashing yourself.

### A body-only collector

Emit an HTML fragment, leave the attachment list empty, seal:

```sh
# uptime collector -- load and uptime in the BODY only.
TAG=uptime
out=$(uptime 2>/dev/null)
{
	printf '<h4>Uptime</h4>\n'
	printf '<pre>\n'; printf '%s\n' "$out" | esc; printf '</pre>\n'
} > "log.$TAG.html"
: > "attachment.$TAG.html"
seal
```

### A collector with an attachment

Summarize in the body, ship the detail as a file, list it, seal:

```sh
# pkgaudit collector -- vulnerable installed packages, last audit, attached.
TAG=pkgaudit
have pkg || exit 0                       # nothing to seal -> skipped
tmp=$(mktemp) || exit 0
pkg audit -F > "$tmp" 2>/dev/null

n=$(grep -c 'is vulnerable' "$tmp" 2>/dev/null) || n=0
{
	printf '<h4>Package audit</h4>\n'
	printf '<p>%s vulnerable package(s) reported.</p>\n' "$n"
} > "log.$TAG.html"
attach "pkg-audit.txt" < "$tmp"
printf '<li>pkg-audit.txt &mdash; vulnerable packages, last audit</li>\n' \
	> "attachment.$TAG.html"
rm -f "$tmp"
seal
```

To ship several files, call `attach` once per distinct `$Y` and add one `<li>`
per file to `attachment.$TAG.html`.

### Checklist

- `TAG` set, unique, no dot.
- Untrusted text piped through `esc`.
- Optional tools guarded with `have`; exit without sealing when there is nothing
  to report.
- `attachment.$TAG.html` written even when empty.
- `seal` is the last line.
- `make check` passes (`sh -n` on your script).
