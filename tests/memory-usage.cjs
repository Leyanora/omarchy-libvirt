const { test } = require('node:test');
const assert = require('node:assert/strict');
const vm = require('node:vm');
const fs = require('node:fs');
const path = require('node:path');
const api = vm.createContext({});
vm.runInContext(fs.readFileSync(path.join(__dirname, '..', 'Virsh.js'), 'utf8'), api);

test('guest memory excludes reclaimable cache and uses the guest total', () => {
  const samples = api.parseDomStats("Domain: 'example-domain'\n" +
    '  balloon.current=4096\n  balloon.available=4000\n' +
    '  balloon.unused=1000\n  balloon.usable=3000\n  balloon.rss=2048\n');
  const sample = samples['d:example-domain'];
  assert.equal(api.memoryUsed(sample), 1000);
  assert.equal(api.memoryTotal(sample), 4000);
  assert.equal(Math.round(api.memoryUsed(sample) / api.memoryTotal(sample) * 100), 25);
});

test('older guest free-memory stats and host RSS retain matching denominators', () => {
  const sample = { current: 1024, available: 900, unused: 300, usable: -1, rss: 700 };
  assert.equal(api.memoryUsed(sample), 600);
  assert.equal(api.memoryTotal(sample), 900);
  sample.unused = -1;
  assert.equal(api.memoryUsed(sample), 700);
  assert.equal(api.memoryTotal(sample), 1024);
});

test('zero available-to-reuse memory is valid and inconsistent counters are bounded', () => {
  const sample = { current: 1024, available: 900, unused: 0, usable: 0, rss: 700 };
  assert.equal(api.memoryUsed(sample), 900);
  sample.usable = 1000;
  assert.equal(api.memoryUsed(sample), 0);
});

test('CPU reflects elapsed CPU time relative to all assigned vCPUs', () => {
  const prev = { at: 1000, cpuTime: 0 };
  assert.equal(api.cpuPercent(prev, 120000000, 2, 4000), 2);
  assert.equal(api.cpuPercent(prev, 6000000000, 2, 4000), 100);
});
