// Run with: node --test tests/virsh-arguments.cjs
// Integration checks use only ephemeral test:///default connections, never QEMU.
const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { spawnSync } = require('node:child_process');

const virsh = vm.createContext({});
vm.runInContext(fs.readFileSync(path.join(__dirname, '..', 'Virsh.js'), 'utf8'), virsh);
const uri = 'test:///default';
const array = value => Array.from(value);

test('domain actions preserve option-like names as explicit values', () => {
  for (const name of ['--help', '--domain', "a 'quoted' VM", '$(touch marker)']) {
    for (const verb of array(virsh.ACTION_VERBS)) {
      assert.deepEqual(array(virsh.actionArgv(uri, verb, name)),
        ['virsh', '-c', uri, verb, '--domain', name]);
    }
  }
  assert.equal(virsh.actionArgv(uri, 'unknown', 'test'), null);
  assert.equal(virsh.actionArgv(uri, 'start', ''), null);
});

test('read-only domain probes use explicit domain values', () => {
  for (const name of ['--name', '--reason', 'ordinary VM']) {
    assert.deepEqual(array(virsh.snapshotListArgv(uri, name)),
      ['virsh', '-c', uri, '-q', 'snapshot-list', '--domain', name, '--name']);
    assert.deepEqual(array(virsh.snapshotCurrentArgv(uri, name)),
      ['virsh', '-c', uri, '-q', 'snapshot-current', '--domain', name, '--name']);
    assert.deepEqual(array(virsh.domInfoArgv(uri, name)),
      ['virsh', '-c', uri, 'dominfo', '--domain', name]);
    assert.deepEqual(array(virsh.domStateArgv(uri, name)),
      ['virsh', '-c', uri, 'domstate', '--domain', name, '--reason']);
  }
});

test('snapshot actions preserve option-like names as explicit values', () => {
  for (const name of ['--current', '--children', '--snapshotname', "a 'quoted' snapshot"]) {
    for (const [builder, verb] of [['snapshotDeleteArgv', 'snapshot-delete'], ['snapshotRevertArgv', 'snapshot-revert']]) {
      assert.deepEqual(array(virsh[builder](uri, '--domain', name)),
        ['virsh', '-c', uri, verb, '--domain', '--domain', '--snapshotname', name]);
    }
  }
});

// Quote for virsh's interactive command parser; not a host shell invocation.
function quote(value) {
  return '"' + value.replace(/\\/g, '\\\\').replace(/"/g, '\\"') + '"';
}
function command(argv) {
  const values = array(argv);
  assert.deepEqual(values.slice(0, 3), ['virsh', '-c', uri]);
  return values.slice(3).map(quote).join(' ');
}
function run(commands) {
  const result = spawnSync('virsh', ['-c', uri], {
    input: commands.join('\n') + '\nquit\n', encoding: 'utf8', timeout: 10000,
    env: { ...process.env, LC_ALL: 'C' }
  });
  assert.ifError(result.error);
  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.stderr, '', result.stderr);
  return result.stdout;
}

for (const name of ['--current', '--children', 'ordinary snapshot', "snapshot'quote"]) {
  test(`deletion targets exactly ${JSON.stringify(name)} and preserves its child`, () => {
    const output = run([
      command(['virsh', '-c', uri, 'snapshot-create-as', '--domain', 'test', '--name', name]),
      command(virsh.snapshotCreateArgv(uri, 'test', 'victim', '')),
      command(virsh.snapshotDeleteArgv(uri, 'test', name)),
      'snapshot-current --domain test --name'
    ]);
    const stored = name;
    assert.ok(output.includes(`Domain snapshot ${stored} deleted`), output);
    assert.match(output, /\nvirsh # snapshot-current --domain test --name\nvictim\n/);
    assert.ok(!output.includes('Domain snapshot victim deleted'), output);
  });
  test(`revert targets exactly ${JSON.stringify(name)} rather than current snapshot`, () => {
    const stored = name;
    const output = run([
      command(['virsh', '-c', uri, 'snapshot-create-as', '--domain', 'test', '--name', name]),
      command(virsh.snapshotCreateArgv(uri, 'test', 'victim', '')),
      command(virsh.snapshotRevertArgv(uri, 'test', stored)),
      'snapshot-current --domain test --name'
    ]);
    assert.ok(output.includes(`\nvirsh # snapshot-current --domain test --name\n${stored}\n`), output);
  });
}
