.import "Virsh.js" as Virsh

// The systemd drop-in that silences omarchy-crash-watch. Pure: no QML, no state.

// Four load-bearing constraints: flock, content compare, marker line, runtime dir.
function buildScript(moduleName, suppress, pattern) {
  return [
    "set -u",
    "umask 077",  // owner-only, rather than leaning on the runtime dir's 0700
    "unit=omarchy-crash-watch.service",
    // Probed on disk, not with `systemctl cat`: that exits 1 from Process.
    "found=0",
    "for d in /usr/lib/systemd/user /etc/systemd/user \"${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user\"; do",
    "  [ -f \"$d/$unit\" ] && found=1",
    "done",
    "[ \"$found\" = 1 ] || exit 0",
    "runtime=\"${XDG_RUNTIME_DIR:-/run/user/$(id -u)}\"",
    "dir=\"$runtime/systemd/user/$unit.d\"",
    "file=\"$dir/50-" + moduleName + ".conf\"",
    // Swept every reconcile so an upgrade from <=1.0.1 cleans up after itself.
    "legacy=\"${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user/$unit.d/50-" + moduleName + ".conf\"",
    "marker='# Managed by the " + moduleName + " Omarchy plugin'",
    "lock=\"$runtime/" + moduleName + ".crash-toggle.lock\"",
    "exec 9>\"$lock\" || exit 0",
    "flock 9 || exit 0",
    "want=" + (suppress ? "1" : "0"),
    // `%` starts a systemd specifier in Environment=; `%%` is the literal.
    "pattern=" + Virsh.shq(String(pattern).replace(/%/g, "%%")),
    "changed=0",
    "if [ -f \"$legacy\" ] && grep -qF \"$marker\" \"$legacy\"; then",
    "  rm -f \"$legacy\" || exit 1",
    "  rmdir \"$(dirname \"$legacy\")\" 2>/dev/null || true",
    "  changed=1",
    "fi",
    "if [ \"$want\" = 1 ]; then",
    "  desired=\"$marker",
    "[Service]",
    "Environment=\\\"OMARCHY_CRASH_IGNORE=$pattern\\\"\"",
    "  if [ ! -f \"$file\" ] || [ \"$(cat \"$file\")\" != \"$desired\" ]; then",
    "    mkdir -p \"$dir\" || exit 1",
    "    printf '%s\\n' \"$desired\" >\"$file.tmp\" && mv \"$file.tmp\" \"$file\" || exit 1",
    "    changed=1",
    "  fi",
    "elif [ -f \"$file\" ] && grep -qF \"$marker\" \"$file\"; then",
    "  rm -f \"$file\" || exit 1",
    "  changed=1",
    "fi",
    "[ \"$changed\" = 1 ] || exit 0",
    "systemctl --user daemon-reload || exit 1",
    "systemctl --user restart \"$unit\" || exit 1"
  ].join("\n")
}

// A quote, newline or trailing backslash all break the Environment= value.
function ignoreIsWritable(pattern) {
  return !/["\n]|\\$/.test(pattern)
}
