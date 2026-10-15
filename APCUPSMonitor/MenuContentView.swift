import SwiftUI
import AppKit

struct MenuContentView: View {
    @ObservedObject var model: UPSMonitorModel
    @State private var showingDiagnostics = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.deviceName)
                        .font(.headline)
                    Text(model.lastSystemRead == nil ? "Status unavailable" : model.powerSourceState)
                        .font(.caption)
                        .foregroundStyle(model.isOnBattery ? .orange : .secondary)
                }
                Spacer()
                statusBadge
            }

            Divider()

            if let updated = model.lastSystemRead {
                HStack {
                    Text("macOS read:")
                    Text(updated.formatted(date: .omitted, time: .standard)).monospacedDigit()
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            } else {
                Text(model.systemStatus)
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                row("Battery", model.batteryPercent.map { "\($0)%" } ?? "—")
                row("Load", model.loadPercent.map { String(format: "%.0f%%", $0) } ?? "—")
                row("Estimated power", model.estimatedWatts.map { String(format: "%.0f W", $0) } ?? "—")
                row("Runtime", model.runtimeMinutes.map { "\($0) min" } ?? "—")
                row("Input voltage", model.lineVoltage.map { String(format: "%.0f V", $0) } ?? "—")
                row("Rated power", String(format: "%.0f W", model.nominalWatts))
            }

            Text("Read-only shared HID access. macOS keeps native UPS management and automatic shutdown.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            HStack(alignment: .center) {
                Button("Refresh") { model.refresh() }
                Button("Diagnostics") { showingDiagnostics.toggle() }
                Spacer()
                Text("v\(appVersion)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .help(fullVersion)
                Button("Quit") { NSApplication.shared.terminate(nil) }
            }
            .buttonStyle(.borderless)

            Toggle("Show data in menu bar", isOn: $model.showMenuBarData)
                .toggleStyle(.switch)
                .font(.caption)

            if showingDiagnostics {
                Divider()
                DiagnosticsView(model: model)
                    .frame(height: 300)
            }
        }
        .padding(14)
        .onAppear { model.refresh() }
    }

    private var statusBadge: some View {
        Text(model.hidStatus)
            .font(.caption2)
            .fixedSize(horizontal: false, vertical: true)
            .help(model.hidStatus)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(.quaternary, in: Capsule())
    }

    @ViewBuilder
    private func row(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Text(value).monospacedDigit()
        }
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.4"
    }

    private var fullVersion: String {
        let version = appVersion
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "5"
        return "APCUPSMonitor v\(version) (\(build))"
    }
}
