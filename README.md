# Omarchy qemu widget

A libvirt frontend for the [Omarchy](https://omarchy.org/) bar. The bar item is
a glyph, dimmed when nothing is running; the popup lists every domain on the
connection with a state light, play/stop controls, and a click-to-open console.

![The popup, listing a running, a paused and two shut off domains](preview.png)

- **Green** running, **amber** paused, **red** shut off. A row only shows the
  buttons its state allows.
- **▶** starts a shut off domain, or resumes a paused one.
- **■** is `virsh shutdown` — a polite ACPI request the guest can ignore.
- **󱐋** is `virsh destroy`. It cuts power and loses unwritten guest state, so
  it takes two clicks: the first arms it, the second does it, and it disarms
  itself after four seconds. A shut off domain has nothing to force off.
- **Clicking a domain's name** opens its console in `virt-viewer` — only while
  the domain is up, since a shut off one has no console to attach to.
- **󰚦** brings the connection up. It only lights up when there is something to
  do — see [Bringing the connection up](#bringing-the-connection-up).

Left click the bar item for the popup, right click to open virt-manager, middle
click or scroll to refresh.

Optionally, it can also stop Omarchy announcing the QEMU segfault that stopping
a VM provokes — off by default, see
[Silencing the shutdown crash toast](#silencing-the-shutdown-crash-toast).

## Prerequisites

```bash
sudo pacman -S qemu-full libvirt virt-manager virt-viewer edk2-ovmf
```

| Package | Why |
|---|---|
| `libvirt` | **Required.** Provides `virsh`, which is the whole backend — the widget shells out to it and reads nothing else |
| `qemu-full` | The hypervisor, plus every guest architecture and its firmware |
| `virt-viewer` | **Required for consoles.** `virt-viewer` is what clicking a domain name opens |
| `virt-manager` | Only the popup's footer button. Skip it and set `"manager": ""` to hide that row |
| `edk2-ovmf` | UEFI firmware for guests. Optional, but a modern guest usually wants it over SeaBIOS |

KVM itself needs no group membership on Arch — `/dev/kvm` is world-writable by
udev rule. Check with `test -w /dev/kvm && echo ok`.

Then pick a connection. The widget's default, `qemu:///session`, is the one
that needs no further setup.

### `qemu:///session` — per-user, no root

Nothing to configure and nothing to start. `virsh` spawns
`virtqemud --timeout=120` under your own user on first contact, and it exits
when idle. Guests get QEMU user-mode networking (`<interface type='user'>`) —
no bridge, no `dnsmasq`, no NAT to set up — and domain and pool definitions
live under `~/.config/libvirt/`. The trade-off is no inbound connections to
guests and no networking between them.

```bash
virsh -c qemu:///session list --all      # should print a header, not an error
```

### `qemu:///system` — host-wide, needs root once

```bash
sudo usermod -aG libvirt $USER           # then log out and back in
sudo pacman -S dnsmasq                   # the default NAT network needs it
sudo systemctl enable --now virtqemud.socket virtnetworkd.socket virtstoraged.socket
sudo virsh net-autostart default
sudo virsh net-start default
```

`dnsmasq` is only an *optional* dependency of `libvirt`, so pacman will not
pull it in — but without it the `default` NAT network cannot hand out DHCP and
refuses to start. Hosts still shipping the monolithic daemon use
`libvirtd.socket` in place of the three split units above.

Point the widget at it in `~/.config/omarchy/shell.json`:

```json
{ "id": "leyanora.libvirt", "uri": "qemu:///system" }
```

Skipping `systemctl enable` is fine — the popup's plug button starts those same
units for the current boot.

## Install

```bash
omarchy plugin add https://github.com/Leyanora/omarchy-libvirt.git --enable
```

The widget expects the connection to work without a password prompt. If
`virsh -c <uri> list --all` works in a terminal it works here; if it does not,
the popup shows you the same error.

## The connection line

Under the title, in place of the URI: **Connected** when libvirt answered the
last poll, **Disconnected** in red when it did not — with the error below it
and the plug button lit. The URI itself is on hover, which matters when two
instances sit in the bar.

## Bringing the connection up

The plug button next to refresh is enabled only when the hypervisor will not
answer, or when a persistent network is down. It does the smallest thing that
makes VMs startable:

- **`qemu:///session`** has no daemon to manage — `virsh` spawns
  `virtqemud --timeout=120` itself on first contact — so the button's only work
  there is starting inactive networks.
- **`qemu:///system`** is behind systemd. The button runs
  `systemctl start virtqemud.socket virtnetworkd.socket virtstoraged.socket`
  (falling back to `libvirtd.socket` on hosts that still ship the monolithic
  daemon), which prompts through Omarchy's polkit agent.

It waits up to five seconds for the connection to answer, then starts any
persistent network that is down. It uses `systemctl start`, never `enable` —
this is "make it work now", not a change to what the machine does at boot.

## Silencing the shutdown crash toast

Stopping a VM tends to raise an Omarchy "Process crashed: qemu-system-x86_64"
notification. That is not this plugin, and not `virt-viewer` either: libvirt
SIGTERMs QEMU, and QEMU segfaults inside its own SPICE teardown on the way out.
The domain log shows the whole story:

```
qemu-system-x86_64: terminating on signal 15 from pid … (/usr/bin/virtqemud)
qemu-system-x86_64: warning: Spice: …spice_server_remove_interface: VD_INTERFACE_REMOVING unsupported
shutting down, reason=shutdown
```

The guest has already stopped by then, so nothing is lost — it is a real
upstream bug with no consequence beyond the toast.

**Why handle it here, in a plugin that does not cause it?** Because this is
where you press the button that triggers it. Every ■ and 󱐋 in the popup ends
in libvirt SIGTERMing QEMU, so the toast is a direct consequence of using the
widget, and the widget is where you would go looking to make it stop. The
filter it writes is Omarchy's own supported one — nothing is patched, nothing
is monkey-patched, and the whole change is a single file that goes away when
you turn the setting off.

```json
{ "id": "leyanora.libvirt", "suppressCrashToasts": true }
```

With that set, the widget keeps a drop-in at
`~/.config/systemd/user/omarchy-crash-watch.service.d/50-leyanora.libvirt.conf`
that sets `OMARCHY_CRASH_IGNORE` for Omarchy's crash watcher, and reloads it.
Setting the key back to `false` removes the file again.

It is **off by default**, because reconfiguring another service is not
something a bar widget should do uninvited. Two things worth knowing before
turning it on:

- The watcher filters on the executable name only, so this also silences a
  QEMU crash that happens *mid-run* — a VM dying under you goes unannounced.
- The widget will only ever delete a drop-in carrying its own marker comment,
  so a file you wrote by hand at that path is left alone.

`omarchy-toggle-crash-capture` remains the way to turn crash announcements off
wholesale, if you would rather not filter per-binary.

## Settings

Every key goes in the widget's entry in `~/.config/omarchy/shell.json`. The
entry is keyed by the plugin id, `leyanora.libvirt` — not by the display name:

```json
{
  "bar": {
    "layout": {
      "right": [
        { "id": "leyanora.libvirt", "uri": "qemu:///system", "interval": 5 }
      ]
    }
  }
}
```

| Key | Default | What it does |
|---|---|---|
| `uri` | `qemu:///session` | libvirt connection URI |
| `interval` | `10` | Poll seconds; floored at 2 |
| `icon` | `󰒋` | Bar glyph |
| `showCount` | `false` | Show the running count next to the glyph |
| `confirmForceOff` | `true` | Require the second click on force off |
| `console` | `virt-viewer --connect {uri} {name}` | Console command; `{uri}` and `{name}` are substituted shell-quoted |
| `manager` | `virt-manager -c <uri>` | The popup's footer action; `""` hides the row |
| `onRightClick` | same as `manager` | Right click on the bar item |
| `colorRunning` | `#3fb950` | State light, running |
| `colorPaused` | `#d29922` | State light, paused |
| `colorStopped` | `#f85149` | State light, shut off |
| `suppressCrashToasts` | `false` | Filter QEMU crash toasts, see below |
| `crashIgnore` | `^qemu-system-` | Regex of executable names to filter when the above is on |

`allowMultiple` is on, so a second entry with `"uri": "qemu:///system"` gives
you both connections side by side in the bar.

## IPC

```bash
omarchy-shell leyanora.libvirt toggle     # also: open, close, show, hide
omarchy-shell leyanora.libvirt refresh    # re-poll on every monitor
```

Bind either in `~/.config/hypr/bindings.lua`.

## How it reads state

Four `virsh` calls per poll regardless of how many domains exist — every
domain, the running ones, the paused ones, and any persistent network that is
down — each line tagged in column 0 so a domain name containing spaces survives
parsing. Everything else is a `virsh <verb> <domain>` with the name
shell-quoted.

One action runs at a time — the buttons disable while it does. `virsh shutdown`
and friends return as soon as the request is queued rather than when the guest
acts on it, so after every action the widget re-polls three times over the next
few seconds instead of once; expect a row to change state a beat after you
click it, not instantly.

The widget is instantiated once per monitor, so the poll runs per bar surface
and IPC refreshes go through `broadcast()`.

## Development

```bash
bin/check        # validate the manifest
bin/dev-link     # symlink this repo into ~/.config/omarchy/plugins/
bin/dev-unlink   # remove it
```

Edit `BarWidget.qml` and save; the shell reloads plugin code on its own. If a
change does not land, `omarchy restart shell`. QML errors are silent in the bar
and loud in `qs -p /usr/share/omarchy/shell log`.

The shell API this widget is built on lives in `/usr/share/omarchy/shell/` —
`Ui/` for the components, `Commons/` for the `Color` and `Style` singletons,
`plugins/` for the first-party widgets worth reading. Read it freely, never
edit it.

## License

MIT — see [LICENSE](LICENSE).
