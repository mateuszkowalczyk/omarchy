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
JS
