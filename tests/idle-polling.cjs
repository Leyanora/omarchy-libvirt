// Run with: node --test tests/idle-polling.cjs
const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const root = path.join(__dirname, '..');
const virsh = vm.createContext({});
vm.runInContext(fs.readFileSync(path.join(root, 'Virsh.js'), 'utf8'), virsh);
const config = vm.createContext({});
vm.runInContext(fs.readFileSync(path.join(root, 'Settings.js'), 'utf8'), config);

test('default pauseWhenIdle=false preserves unconditional periodic polling', () => {
  assert.equal(virsh.shouldPoll(false, false, 0, 0, false, false), true);
  assert.equal(config.read({}, 'pauseWhenIdle', false), false);
});

test('pauseWhenIdle=true disables polling while idle so session daemons can time out', () => {
  assert.equal(virsh.shouldPoll(true, false, 0, 0, false, false), false);
  assert.equal(virsh.shouldPoll(true, false, -1, 0, false, false), false);
});

test('pauseWhenIdle=true activates polling when popup is open or any domain is live/in transition', () => {
  assert.equal(virsh.shouldPoll(true, true, 0, 0, false, false), true);
  assert.equal(virsh.shouldPoll(true, false, 1, 0, false, false), true);
  assert.equal(virsh.shouldPoll(true, false, 0, 1, false, false), true);
  assert.equal(virsh.shouldPoll(true, false, 0, 0, true, false), true);
  assert.equal(virsh.shouldPoll(true, false, 0, 0, false, true), true);
});

test('pauseWhenIdle is exposed in Settings and wired through BarWidget and Service', () => {
  const behaviours = Array.from(config.BEHAVIOUR_SETTINGS).map(entry => entry.name);
  assert.ok(behaviours.includes('pauseWhenIdle'));

  const settingsQml = fs.readFileSync(path.join(root, 'Settings.qml'), 'utf8');
  const serviceQml = fs.readFileSync(path.join(root, 'Service.qml'), 'utf8');
  const barWidgetQml = fs.readFileSync(path.join(root, 'BarWidget.qml'), 'utf8');

  assert.match(settingsQml, /readonly property bool pauseWhenIdle:\s*read\("pauseWhenIdle",\s*false\)/);
  assert.match(settingsQml, /case "pauseWhenIdle":\s*return pauseWhenIdle/);
  assert.match(barWidgetQml, /popupOpen:\s*root\.popupOpen/);
  assert.match(barWidgetQml, /pauseWhenIdle:\s*config\.pauseWhenIdle/);
  assert.match(serviceQml, /property bool popupOpen:\s*false/);
  assert.match(serviceQml, /property bool pauseWhenIdle:\s*false/);
  assert.match(serviceQml, /readonly property bool activePolling:\s*Virsh\.shouldPoll\(/);
  assert.match(serviceQml, /id:\s*pollTimer[^}]*running:\s*service\.activePolling/);
  assert.doesNotMatch(serviceQml, /id:\s*pollTimer[^}]*triggeredOnStart:\s*true/);
  assert.match(serviceQml, /Component\.onCompleted:\s*if\s*\(!poll\.running\)\s*refresh\(\)/);
});
