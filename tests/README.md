# Bar usage tests

Requires Node.js 18+; no npm packages are needed.

```bash
node --test tests/*.cjs
```

These tests load the actual JavaScript helpers without importing QML. They cover
compact and named bar readouts, aliases, domain selection by real name, Unicode
truncation, overflow, configuration limits, RAM percentages and guest memory
statistics including cache and fallback behavior.

They do not connect to libvirt or modify VMs. Node is a development-only test
dependency; the plugin's runtime dependencies are unchanged. Graphical behavior
requires a separate Omarchy session check.
