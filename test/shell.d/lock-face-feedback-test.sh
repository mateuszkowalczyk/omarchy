#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const fs = require('fs')
const serviceQml = fs.readFileSync(path.join(root, 'shell/plugins/lock/Service.qml'), 'utf8')
const lockViewQml = fs.readFileSync(path.join(root, 'shell/plugins/lock/LockView.qml'), 'utf8')

assert(
  /property string faceStatus: ""/.test(serviceQml) && /property string faceStatus: ""/.test(lockViewQml),
  'the camera reports through its own field slot rather than the password one'
)

// Face runs on ambient activity, so an empty room must not paint the field red
// or read back as a rejected credential.
const faceFunctions = serviceQml.match(/function (?:startFaceAttempt|finishFaceAttempt|stopFaceAuthentication)\([\s\S]*?\n  \}/g) || []
assert(faceFunctions.length === 3, 'the three face lifecycle functions are present')
for (const fn of faceFunctions) {
  assert(!fn.includes('failureMessage'), 'no face lifecycle function writes the password failure message')
}

assert(
  /readonly property bool errorState: failureMessage\.length > 0/.test(lockViewQml),
  'the error border stays keyed to the password alone'
)

const facePamMatch = serviceQml.match(/PamContext \{\s*id: facePam([\s\S]*?)\n  \}/)
assert(facePamMatch, 'the lock service has an independent face PAM context')
assert(
  /onMessageChanged: \{\s*if \(root\.faceAuthenticating && message\) root\.faceStatus = message/.test(facePamMatch[1]),
  'the backend own conversation text drives the field, so no wording is backend-specific'
)

assert(
  /if \(faceAttemptCount === 0\) faceStatus = "Looking for your face…"/.test(serviceQml),
  'a burst opens with our own wording, so a silent backend still explains the delay'
)

assert(
  /faceAttemptCount = 0\s*faceStatus = "Face not recognized"/.test(serviceQml),
  'the burst reports once when its budget is spent, not after each attempt'
)

assert(
  /function stopFaceAuthentication\(\)[\s\S]*faceStatus = ""/.test(serviceQml) &&
    /if \(succeeded\) \{\s*faceAttemptCount = 0\s*faceStatus = ""/.test(serviceQml),
  'success and cleanup both clear the face status'
)

assert(
  /readonly property string fieldStatusText: authenticatingPassword\s*\? "Checking…"\s*: \(errorState \? failureMessage : \(faceStatus\.length > 0 \? faceStatus : placeholderText\)\)/.test(lockViewQml),
  'a password check outranks a rejected password, which outranks the camera'
)

assert(
  /text: root\.fieldStatusText/.test(lockViewQml),
  'the field renders the ranked status rather than its own conditional'
)

const lockViewBindings = serviceQml.match(/^ +faceStatus: .*$/gm) || []
assert(
  lockViewBindings.length === 2 &&
    lockViewBindings.filter(line => line.includes('root.faceStatus')).length === 1,
  'both views take face status, but only the live one is fed; the preview is inert'
)

// The status text hides as soon as the field has characters, and typing starts a
// burst, so the glyph is the only face feedback left on that path.
assert(
  /property bool faceScanning: false/.test(lockViewQml),
  'the view is told when the camera is running, not left to read it out of the wording'
)

const scanningBindings = serviceQml.match(/^ +faceScanning: .*$/gm) || []
assert(
  scanningBindings.length === 2 &&
    scanningBindings.filter(line => line.includes('root.faceScanning')).length === 1,
  'both views take the scanning flag, but only the live one is fed'
)

const faceIcon = lockViewQml.match(/Text \{\s*id: faceIcon([\s\S]*?)\n      \}/)
assert(faceIcon, 'the lock view still draws a face indicator')
assert(
  /opacity: root\.faceScanning \? 1 : 0\.55/.test(faceIcon[1]),
  'the glyph fades while the camera is idle and comes up full while it runs'
)
// tokyo-night ships a shell.lock.toml that flattens every lock color to one
// value, so state carried by a color swap would be invisible there.
assert(
  /color: Color\.lock\.placeholder/.test(faceIcon[1]),
  'the glyph keeps one color, so a theme that flattens the lock palette still shows the state'
)
assert(
  !/errorState|failureMessage/.test(faceIcon[1]),
  'the glyph never takes the error treatment, so a scan cannot read as a rejection'
)
JS
