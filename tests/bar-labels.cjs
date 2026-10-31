const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const root = path.join(__dirname, '..');
const virsh = vm.createContext({});
vm.runInContext(fs.readFileSync(path.join(root, 'Virsh.js'), 'utf8'), virsh);
const ui = vm.createContext({ Virsh: virsh });
vm.runInContext(fs.readFileSync(path.join(root, 'Interface.js'), 'utf8')
  .replace(/^\.import .*$/mg, ''), ui);
const config = vm.createContext({});
vm.runInContext(fs.readFileSync(path.join(root, 'Settings.js'), 'utf8'), config);
const domains = [
  { name: 'example-domain-long-name', domainState: 'running' },
  { name: 'guest-b', domainState: 'running' },
  { name: 'off', domainState: 'shut off' }
];
const stats = { 'd:example-domain-long-name': { cpu: 12 }, 'd:guest-b': { cpu: 3 } };
test('defaults preserve upstream truncation and display', () => {
  assert.equal(ui.barStatsText(domains, stats, []), 'example-dom… 12% · guest-b 3%');
});
test('compact mode hides names while preserving independent percentages', () => {
  assert.equal(ui.barStatsText(domains, stats, [], false), '12% · 3%');
  assert.equal(ui.barStatsText(domains, stats, ['guest-b'], false), '3%');
});
test('aliases affect only displayed labels, never domain selection or commands', () => {
  const aliases = { 'd:example-domain-long-name': 'vm-a' };
  assert.equal(ui.barStatsText(domains, stats, [], true, 12, aliases), 'vm-a 12% · guest-b 3%');
  assert.equal(ui.barStatsText(domains, stats, ['vm-a'], true, 12, aliases), '');
  assert.equal(virsh.actionArgv('test:///default', 'start', domains[0].name).at(-1), domains[0].name);
});
test('custom limits truncate labels and preserve Unicode code points', () => {
  assert.equal(ui.barStatsText(domains, stats, ['guest-b'], true, 4), 'gue… 3%');
  assert.equal(ui.barStatsText(domains, stats, ['guest-b'], true, 1), '… 3%');
  assert.equal(ui.barStatsText(domains, stats, ['guest-b'], true, 2, { 'd:guest-b': '😀😀😀' }), '😀… 3%');
});
test('clearing aliases restores names without mutating the previous config', () => {
  const old = { 'd:guest-b': 'vm-b', 'd:other': 'other' };
  const next = config.withBarAlias(old, 'guest-b', '   ');
  assert.equal(next['d:guest-b'], undefined);
  assert.equal(next['d:other'], 'other');
  assert.equal(old['d:guest-b'], 'vm-b');
  assert.equal(config.withBarAlias(old, '__proto__', ' short ')['d:__proto__'], 'short');
});
test('empty aliases fall back to real names and missing samples stay hidden', () => {
  assert.equal(ui.barStatsText(domains, stats, ['guest-b'], true, 12, { 'd:guest-b': ' ' }), 'guest-b 3%');
  assert.equal(ui.barStatsText(domains, {}, [], false), '');
});
test('compact display keeps the existing overflow indicator', () => {
  const list = Array.from({ length: 5 }, (_, i) => ({ name: `vm${i}`, domainState: 'running' }));
  const samples = Object.fromEntries(list.map(d => [`d:${d.name}`, { cpu: 7 }]));
  assert.equal(ui.barStatsText(list, samples, [], false), '7% · 7% · 7% · +2');
});
test('name limits are bounded and non-finite values reset to the default', () => {
  assert.equal(config.barNameLength(-10), 1);
  assert.equal(config.barNameLength(100), 40);
  assert.equal(config.barNameLength(Infinity), 12);
  assert.equal(config.barNameLength('invalid'), 12);
});

test('optional memory readout labels CPU and RAM independently for each VM', () => {
  const samples = {
    'd:example-domain-long-name': { cpu: 2, memUsed: 1.4 * 1024 * 1024, memTotal: 4 * 1024 * 1024 },
    'd:guest-b': { cpu: 3, memUsed: 512 * 1024, memTotal: 1024 * 1024 }
  };
  assert.equal(ui.barStatsText(domains, samples, [], false, 12, {}, true),
    'c:2% r:35% · c:3% r:50%');
  assert.equal(ui.barStatsText(domains, samples, ['guest-b'], true, 12, { 'd:guest-b': 'vm-b' }, true),
    'vm-b c:3% r:50%');
});

test('memory distinguishes zero and unavailable values; first CPU sample stays unknown', () => {
  for (const value of [undefined, NaN, Infinity, -1]) {
    assert.equal(ui.barStatsText(domains, { 'd:guest-b': { cpu: -1, memUsed: value, memTotal: 1024 } },
      ['guest-b'], false, 12, {}, true), 'c:– r:–');
  }
  assert.equal(ui.barStatsText(domains, { 'd:guest-b': { cpu: 0, memUsed: 0, memTotal: 1024 } },
    ['guest-b'], false, 12, {}, true), 'c:0% r:0%');
});


test('RAM percentage requires a valid allocation and is capped at 100%', () => {
  for (const total of [undefined, 0, -1, NaN, Infinity]) {
    assert.equal(ui.barStatsText(domains, { 'd:guest-b': { cpu: 2, memUsed: 512, memTotal: total } },
      ['guest-b'], false, 12, {}, true), 'c:2% r:–');
  }
  assert.equal(ui.barStatsText(domains, { 'd:guest-b': { cpu: 2, memUsed: 2048, memTotal: 1024 } },
    ['guest-b'], false, 12, {}, true), 'c:2% r:100%');
});
