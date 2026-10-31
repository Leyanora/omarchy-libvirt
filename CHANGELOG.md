# Changelog

Notable changes to Omarchy qemu widget. Versions are the `version` field in
`manifest.json`, and follow [semantic versioning](https://semver.org/spec/v2.0.0.html).

## [1.10.0] — 2026-10-31

- **More compact bar readouts** (#6). Under *Bar labels* in the settings view,
  the bar readout can drop domain names (just the icon and CPU), add memory as
  `c:2% r:35%`, cap labels at 1–40 characters, and use a per-domain alias.
  Aliases change only the bar label, never the tooltip, the popup or a virsh
  command. *CPU usage in the bar* is now *Usage in the bar*.
- New settings: `barShowNames`, `barMemory`, `barNameLength` and `barAliases`.
- **Memory leaves out reclaimable cache.** With balloon statistics it is now
  guest total minus available memory (`MemTotal - MemAvailable`), falling back
  to total minus free on older guests and to host RSS without statistics.
  Guest figures are measured against the guest total, not the allocation.
- **Names starting with `-` are passed to virsh as names** (#5). Domain and
  snapshot names now go through `--domain` and `--snapshotname`, so a snapshot
  called `--current` reverts or deletes that snapshot and not another one.
- The popup now scrolls when the settings view is taller than the screen.
- Node tests in `tests/` cover virsh argv, bar labels and memory figures
  (`node --test tests/*.cjs`).

## [1.9.0] — 2026-10-22

- **CPU and memory per domain** (#4). Running rows show CPU and memory in use,
  each with a hairline gauge. The expanded row spells them out as
  `41% of 2 vCPU · 2.6 / 4 GiB`. 100% CPU means every assigned vCPU is busy.
- **Optional CPU readout in the bar**, `name 41%` per running domain, off by
  default and narrowed to chosen domains from the settings view.
- One `virsh domstats` call samples every running domain. It runs only while
  the popup is open or the bar readout is on, every `statsInterval` seconds
  (default 3).
- New settings: `showStats`, `barStats`, `barDomains` and `statsInterval`.

## [1.8.1] — 2026-10-17

- **Removed crash-toast suppression.** The widget no longer writes a systemd
  drop-in for `omarchy-crash-watch.service`, and the settings view lost its
  "Suppress qemu crash notifications" switch. `suppressCrashToasts` and
  `crashIgnore` in `shell.json` are now ignored. A drop-in an earlier version
  wrote lives in `$XDG_RUNTIME_DIR` and is gone at the next login; to drop it
  sooner:

  ```bash
  rm -f "$XDG_RUNTIME_DIR/systemd/user/omarchy-crash-watch.service.d/50-leyanora.libvirt.conf"
  systemctl --user daemon-reload
  systemctl --user restart omarchy-crash-watch.service
  ```

## [1.7.0] — 2026-08-26

- **Keyboard navigation.** The popup takes focus and carries a row cursor:
  arrows move it, `Enter` runs the row's obvious verb, `x` force-offs or deletes,
  and `s` `c` `r` `,` `/` `Esc` reach the rest. Required moving the popup from
  `PopupCard` to `KeyboardPanel` — an xdg-popup never receives keys.
- **The rest of the settings are editable from the cogwheel**: the connection
  URI, the poll interval, and the five behaviour switches that until now meant
  hand-editing `shell.json`.
- **Domain detail in the expanded row** — vCPU, memory, and why a domain is off.
- **Stalled shutdowns are visible.** A `virsh shutdown` the guest ignores turns
  the row's force-off button red rather than looking like a dead button.
- **Filter field** past eight domains, a **current-snapshot marker**, an armed
  control that **draws its four-second window down**, and a bar glyph that
  **carries state** rather than only a count.

## [1.6.0] — 2026-08-19

- Split the single `BarWidget.qml` into eleven components and four pure
  JavaScript modules, one responsibility each.
- The expanded row's action pills became icon-only chips.

## [1.5.2] — 2026-08-18

- Removed the guest IP readout and its `virsh domifaddr` probe. The widget
  drives domains and never reports a way to reach one.

## [1.5.0] — 2026-08-17

- **Colour picker** for the three state lights, and `crashIgnore` so the
  crash-toast filter is not fixed to `^qemu-system-`.

## [1.4.1] — 2026-08-17

- Security pass: argv rather than a shell for every domain action, prefixed
  lookup keys, and `Text.PlainText` pinned wherever a name is rendered.

## [1.4.0] — 2026-08-17

- **Settings view** behind the cogwheel, and the first setting the popup writes
  back to `shell.json` itself. `suppressCrashToasts` now defaults to off.

## [1.3.0] — 2026-08-16

- **Expandable rows** — pause, reboot and save state.
- **Snapshots** — list, create, revert and delete, the destructive ones behind
  arm-then-confirm.

## [1.2.0] — 2026-08-16

- Connection status under the popup title, with virsh's own error when it fails.

## [1.1.0] — 2026-08-16

- The crash-toast drop-in moved to `$XDG_RUNTIME_DIR`, so it cannot outlive an
  uninstall — Omarchy has no uninstall hook for plugins.

## [1.0.1] — 2026-08-15

- Rewrote the widget around one poll script with tagged output lines, so a
  domain name containing spaces parses correctly.

## [1.0.0] — 2026-08-15

- First release: state light and power controls per domain, click-to-open
  console, virt-manager footer, and the QEMU crash-toast filter.
