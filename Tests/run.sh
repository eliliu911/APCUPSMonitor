#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/module-cache
swiftc -parse-as-library -module-cache-path .build/module-cache \
  Tests/RegressionTests.swift APCUPSMonitor/SnapshotProcess.swift \
  APCUPSMonitor/UPSMonitorModel.swift APCUPSMonitor/SystemUPSReader.swift \
  APCUPSMonitor/HIDUPSReader.swift -framework IOKit -framework AppKit \
  -o .build/RegressionTests
.build/RegressionTests
