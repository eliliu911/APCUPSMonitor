#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/module-cache
if [[ "${1:-}" == "--reader" ]]; then
  swiftc -O -parse-as-library -module-cache-path .build/module-cache \
    Tests/MemoryStress.swift APCUPSMonitor/SnapshotProcess.swift -o .build/MemoryStress
  exec .build/MemoryStress 2000
fi
swiftc -O -parse-as-library -module-cache-path .build/module-cache \
  Tests/UIStress.swift APCUPSMonitor/StatusItemController.swift \
  APCUPSMonitor/MenuContentView.swift APCUPSMonitor/DiagnosticsView.swift \
  APCUPSMonitor/UPSMonitorModel.swift APCUPSMonitor/SnapshotProcess.swift \
  APCUPSMonitor/SystemUPSReader.swift APCUPSMonitor/HIDUPSReader.swift \
  -framework AppKit -framework SwiftUI -framework IOKit -o .build/UIStress
.build/UIStress "$@"
