import AppKit
import SwiftUI
import Combine

/// The long-lived menu-bar item is AppKit-owned. SwiftUI only exists while the
/// popover is open, so background snapshots cannot grow a MenuBarExtra graph.
@MainActor
final class StatusItemController: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private let model: UPSMonitorModel
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var statusSubscription: AnyCancellable?

    override init() {
        model = UPSMonitorModel()
        super.init()
    }

    init(model: UPSMonitorModel) {
        self.model = model
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item
        item.button?.target = self
        item.button?.action = #selector(togglePopover)
        item.button?.imagePosition = .imageLeading
        item.button?.toolTip = "APC UPS Monitor"

        statusSubscription = Publishers.CombineLatest4(
            model.$estimatedWatts, model.$loadPercent, model.$batteryPercent, model.$isOnBattery
        )
        .combineLatest(model.$showMenuBarData)
        .map { values, showData in
            let (watts, load, battery, onBattery) = values
            return StatusLabel(title: showData ? UPSMonitorModel.title(watts: watts, load: load, battery: battery) : "",
                        onBattery: onBattery)
        }
        .removeDuplicates()
        .sink { [weak self] state in
            // Model mutations and the initial subscription occur on MainActor.
            MainActor.assumeIsolated { self?.updateLabel(state) }
        }
    }

    private struct StatusLabel: Equatable {
        let title: String
        let onBattery: Bool
    }

    private func updateLabel(_ state: StatusLabel) {
        guard let button = statusItem?.button else { return }
        button.title = state.title.isEmpty ? "" : " " + state.title
        button.imagePosition = state.title.isEmpty ? .imageOnly : .imageLeading
        button.image = NSImage(systemSymbolName: state.onBattery ? "battery.75percent" : "bolt.fill",
                               accessibilityDescription: state.onBattery ? "UPS Battery" : "AC Power")
        button.image?.isTemplate = true
    }

    @objc func togglePopover() {
        if let popover, popover.isShown {
            popover.performClose(nil)
            return
        }
        guard let button = statusItem?.button else { return }
        let panel = NSPopover()
        panel.behavior = .transient
        panel.animates = false
        panel.delegate = self
        panel.contentViewController = NSHostingController(
            rootView: MenuContentView(model: model).frame(width: 320)
        )
        popover = panel
        panel.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    func popoverDidClose(_ notification: Notification) {
        // Destroy the hosting graph, including diagnostic lists and date text.
        // A new, current view is created on the next click.
        popover?.contentViewController = nil
        popover = nil
    }

    func applicationWillTerminate(_ notification: Notification) {
        statusSubscription = nil
        popover?.close()
        if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
        statusItem = nil
        model.prepareForSleep()
    }
}
