#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const fs = require('fs')
const serviceQml = fs.readFileSync(path.join(root, 'shell/plugins/lock/Service.qml'), 'utf8')

// The fingerprint PAM stays armed for the whole lock waiting for a finger, so
// `authenticating` is true from lock until unlock on every machine with a
// reader enrolled. Gating the blank on it leaves the panel lit all night.
assert(
  /readonly property bool faceScanning: faceAttemptCount > 0/.test(serviceQml),
  'a burst spans the retry gaps, so the timer cannot re-arm between attempts'
)

assert(
  /readonly property bool blockingBlank: authenticatingPassword \|\| faceScanning/.test(serviceQml),
  'only password entry and a face burst hold the display up, never fingerprint'
)

assert(
  /if \(root\.lockRequested && !root\.blockingBlank\) root\.runBlank\(\)/.test(serviceQml),
  'only a bounded check in flight stops the blank timer from blanking'
)

assert(
  !/idleBlankTimer[\s\S]*?!root\.authenticating\)/.test(serviceQml),
  'the blank timer never gates on the combined authenticating state'
)

assert(
  /onBlockingBlankChanged: \{\s*if \(!lockRequested\) return\s*if \(blockingBlank\) idleBlankTimer\.stop\(\)\s*else armBlankTimer\(\)/.test(serviceQml),
  'the blank timer is held off by a bounded check and re-armed when it finishes'
)

assert(
  !/onAuthenticatingChanged:/.test(serviceQml),
  'the combined authenticating state no longer drives the blank timer'
)
JS
