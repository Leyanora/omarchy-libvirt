const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { spawnSync } = require('node:child_process');
const root = path.join(__dirname, '..');
const virsh = vm.createContext({});
vm.runInContext(fs.readFileSync(path.join(root, 'Virsh.js'), 'utf8'), virsh);
const ui = vm.createContext({ Virsh: virsh });
vm.runInContext(fs.readFileSync(path.join(root, 'Interface.js'), 'utf8')
  .replace(/^\.import .*$/mg, ''), ui);

test('a missing virsh is its own state, not a refused connection', () => {
  const result = virsh.parsePoll('X Install the libvirt package, which provides virsh.\n');
  assert.equal(result.missing, true);
  assert.equal(result.error, 'Install the libvirt package, which provides virsh.');
  assert.equal(result.domains.length, 0);
  assert.equal(ui.connectionLabel(true, true), 'Not installed');
});

test('a refused connection and a healthy poll are not missing', () => {
  const refused = virsh.parsePoll('E failed to connect to the hypervisor\n');
  assert.equal(refused.missing, false);
  assert.equal(ui.connectionLabel(true, false), 'Disconnected');
  const healthy = virsh.parsePoll('R dev vm\nP ci runner\nA dev vm\nA ci runner\nA qa\n');
  assert.equal(healthy.missing, false);
  assert.equal(healthy.error, '');
  assert.deepEqual(Array.from(healthy.domains, (d) => d.domainState), ['paused', 'running', 'shut off']);
  assert.equal(ui.connectionLabel(false, false), 'Connected');
});

test('the poll script reports a missing virsh with the X tag', () => {
  const bash = spawnSync('sh', ['-c', 'command -v bash'], { encoding: 'utf8' }).stdout.trim();
  const run = spawnSync(bash, ['-c', virsh.pollScript('test:///default')],
    { env: { PATH: '/nonexistent' }, encoding: 'utf8' });
  assert.equal(run.status, 0);
  assert.equal(virsh.parsePoll(run.stdout).missing, true);
});

test('commandName finds the program a console template starts', () => {
  assert.equal(virsh.commandName('virt-viewer --connect {uri} {name}'), 'virt-viewer');
  assert.equal(virsh.commandName('  GDK_BACKEND=wayland  remote-viewer {name}'), 'remote-viewer');
  assert.equal(virsh.commandName('/usr/bin/virt-viewer {name}'), '/usr/bin/virt-viewer');
  assert.equal(virsh.commandName(''), '');
});

test('commandName gives up on anything the shell would rewrite', () => {
  for (const t of ["'my viewer' {name}", '"$HOME/bin/v" {name}', '$VIEWER {name}',
    '`which v` {name}', 'a\\ b {name}', '{uri}', '(v)', 'a;b', 'x|y'])
    assert.equal(virsh.commandName(t), '', t);
});

test('commandCheckArgv passes the name positionally, never as script text', () => {
  const argv = virsh.commandCheckArgv('x; touch /tmp/pwned');
  assert.equal(argv[argv.length - 1], 'x; touch /tmp/pwned');
  assert.equal(argv[2].includes('pwned'), false);
  const found = spawnSync(argv[0], ['-c', argv[2], 'bash', 'bash'], { encoding: 'utf8' });
  assert.equal(found.status, 0);
  const lost = spawnSync(argv[0], ['-c', argv[2], 'bash', 'no-such-viewer-xyz'], { encoding: 'utf8' });
  assert.notEqual(lost.status, 0);
});

test('a missing tool outranks the error it causes, and names its package', () => {
  const missing = ui.notice('', 'Install the libvirt package, which provides virsh.', '', true, '');
  assert.equal(missing.title, 'virsh is missing');
  assert.deepEqual([...missing.commands], ['sudo pacman -S libvirt qemu-full virt-viewer']);
  assert.equal(missing.glyph, ui.Glyph.notInstalled);
  assert.equal(ui.notice('', 'refused', '', false, '').title, 'No connection');
  assert.equal(ui.notice('', 'refused', '', false, '').body, 'refused');
});

test('the console notice names the package only for the default viewer', () => {
  const viewer = ui.notice('', '', '', false, 'virt-viewer');
  assert.equal(viewer.title, 'virt-viewer is missing');
  assert.deepEqual([...viewer.commands], ['sudo pacman -S virt-viewer']);
  assert.match(viewer.body, /spice-gtk/);
  const custom = ui.notice('', '', '', false, 'rv<b>');
  assert.equal(custom.title, 'rvb> is missing');
  assert.deepEqual([...custom.commands], []);
});

const SYSTEM = 'qemu:///system';
const SESSION = 'qemu:///session';

test('session setup never shows the system-only steps', () => {
  const missing = ui.notice('', '', '', true, '', SESSION).commands.join('\n');
  assert.doesNotMatch(missing, /usermod|systemctl|net-start|dnsmasq/);
  assert.deepEqual([...ui.notice('', 'refused', '', false, '', SESSION).commands], []);
});

test('qemu:///system names the group, the sockets and the default network', () => {
  const missing = ui.notice('', '', '', true, '', SYSTEM).commands;
  assert.equal(missing[0], 'sudo pacman -S libvirt qemu-full virt-viewer');
  assert.ok(missing.includes('sudo pacman -S dnsmasq'));
  const down = ui.notice('', 'Permission denied', '', false, '', SYSTEM);
  assert.equal(down.body, 'Permission denied');
  const lines = down.commands.join('\n');
  assert.match(lines, /usermod -aG libvirt \$USER/);
  assert.match(lines, /systemctl enable --now virtqemud\.socket virtnetworkd\.socket virtstoraged\.socket/);
  assert.match(lines, /net-autostart default/);
  assert.match(lines, /net-start default/);
});

test('a stopped network or a missing dnsmasq gets its own fix', () => {
  const net = ui.notice('', '', "Requested operation is not valid: network 'lab' is not active", false, '');
  assert.equal(net.title, 'Network not started');
  assert.deepEqual([...net.commands], ['sudo virsh net-autostart lab', 'sudo virsh net-start lab']);
  const odd = ui.notice('', '', "network 'a; rm -rf ~' is not active", false, '');
  assert.deepEqual([...odd.commands], ['sudo virsh net-autostart default', 'sudo virsh net-start default']);
  const dns = ui.notice('', '', 'Cannot check dnsmasq binary dnsmasq: No such file or directory', false, '');
  assert.equal(dns.title, 'dnsmasq is missing');
  assert.deepEqual([...dns.commands], ['sudo pacman -S dnsmasq']);
});

test('precedence: settings, then virsh, then connection, then console, then action', () => {
  assert.equal(ui.notice('bad hex', 'x', 'y', true, 'v').title, 'Setting not saved');
  assert.equal(ui.notice('', 'x', 'y', false, 'v').title, 'No connection');
  assert.equal(ui.notice('', '', 'y', false, 'v').title, 'v is missing');
  assert.equal(ui.notice('', '', 'y', false, '').title, 'virsh refused');
  assert.equal(ui.notice('', '', '', false, ''), null);
});
