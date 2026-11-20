// Static guardrail tests only: these do not launch QML, virsh, libvirt or a VM.
const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.join(__dirname, '..');
const guarded = fs.readFileSync(path.join(root, 'GuardedProcess.qml'), 'utf8');
const service = fs.readFileSync(path.join(root, 'Service.qml'), 'utf8');

test('guarded process enforces deadline, escalation, and stream byte limits', () => {
  assert.match(guarded, /property int timeoutMs:\s*10000/);
  assert.match(guarded, /root\.signal\(15\)/);
  assert.match(guarded, /root\.signal\(9\)/);
  assert.equal((guarded.match(/waitForEnd:\s*false/g) || []).length, 2);
  assert.match(guarded, /data\.byteLength > root\.maxStdoutBytes/);
  assert.match(guarded, /data\.byteLength > root\.maxStderrBytes/);
  assert.doesNotMatch(guarded, /data\.length/);
});

test('every Service process surface uses GuardedProcess', () => {
  const guardedCount = (service.match(/\bGuardedProcess\s*\{/g) || []).length;
  assert.equal(guardedCount, 8);
  assert.doesNotMatch(service, /(^|\n)\s*Process\s*\{/);
  assert.match(service, /readonly property int actionTimeoutMs:\s*30000/);
  assert.match(service, /readonly property int maxProbeOutputBytes:\s*1048576/);
});
