# Tests

Requires Node.js 18+; no npm packages are needed. The argument tests also need
`virsh` with libvirt's test driver.

```bash
node --test tests/*.cjs
```

These tests load the actual JavaScript helpers without importing QML. Node is a
development-only test dependency; the plugin's runtime dependencies are
unchanged. Graphical behavior requires a separate Omarchy session check.

## Argument regression tests

`virsh-arguments.cjs` checks argv construction and real virsh parsing. Its
integration tests keep each scenario in one ephemeral `test:///default`
connection so that snapshot state survives between commands. They never use
QEMU system/session connections, real guests or disk images.

Coverage includes leading-dash domain arguments and deletion/reversion of
snapshots named `--current`, `--children`, names with spaces and apostrophes.
Deleting a parent must preserve the other snapshot; reverting must select the
requested snapshot rather than implicitly using the current one.

## Bar usage tests

`bar-labels.cjs` and `memory-usage.cjs` cover compact and named bar readouts,
aliases, domain selection by real name, Unicode truncation, overflow,
configuration limits, RAM percentages and guest memory statistics including
cache and fallback behavior. They do not connect to libvirt or modify VMs.

## Missing tool tests

`missing-tools.cjs` covers the two install gaps the widget reports: the poll's
`X` line when `virsh` is not on `PATH` (run for real with an empty `PATH`), and
the console check — which program a `console` template starts, giving up on
anything quoted or expanded, and passing that name to `command -v` positionally
so it is never script text. It needs `bash` but not libvirt.
