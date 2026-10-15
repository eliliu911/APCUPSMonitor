import SwiftUI

struct DiagnosticsView: View {
    @ObservedObject var model: UPSMonitorModel

    var body: some View {
        TabView {
            VStack(alignment: .leading, spacing: 12) {
                let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.4"
                let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "5"
                Text("Version: v\(version) (build \(build))")
                    .fontWeight(.medium)
                Text("macOS: \(model.systemStatus)")
                if let date = model.lastSystemRead {
                    Text("Last macOS read: \(date.formatted(date: .abbreviated, time: .standard))")
                }
                Text("HID: \(model.hidStatus)")
                if let date = model.lastHIDRead {
                    Text("Last HID values: \(date.formatted(date: .abbreviated, time: .standard))")
                }
                Text("Reads time out after 5 seconds. Unavailable HID is retried every 30 seconds. Refresh retries immediately when the previous read has ended.")
                Text("Read times confirm a successful API query; macOS may itself return cached UPS values.")
                Spacer()
            }
            .font(.caption)
            .textSelection(.enabled)
            .padding()
            .tabItem { Text("Health") }

            List(model.systemDictionary.keys.sorted(), id: \.self) { key in
                HStack(alignment: .top) {
                    Text(key)
                        .font(.caption)
                    Spacer()
                    Text(model.systemDictionary[key] ?? "")
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                }
            }
            .tabItem { Text("macOS") }

            List(model.hidElements) { element in
                HStack {
                    Text(element.usageHex)
                        .font(.caption.monospaced())
                        .frame(width: 90, alignment: .leading)
                    Text("v=\(element.value)")
                        .font(.caption.monospaced())
                    Spacer()
                    Text("r\(element.reportID)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .tabItem { Text("HID") }
        }
    }
}
