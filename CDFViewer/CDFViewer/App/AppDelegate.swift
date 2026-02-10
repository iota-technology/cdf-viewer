import AppKit
import SwiftUI

/// App delegate that manages NSDocument-based architecture
class AppDelegate: NSObject, NSApplicationDelegate {

    /// Registry to track view models for auxiliary windows
    var viewModelRegistry: [ObjectIdentifier: CDFViewModel] = [:]

    /// Chart windows keyed by viewModel
    var chartWindows: [ObjectIdentifier: NSWindow] = [:]

    /// Globe windows keyed by viewModel
    var globeWindows: [ObjectIdentifier: NSWindow] = [:]

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Register for auxiliary window notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleOpenAuxiliaryWindow(_:)),
            name: .openAuxiliaryWindow,
            object: nil
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        NotificationCenter.default.removeObserver(self)
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        false  // Don't create untitled documents - this is a viewer
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            // No visible windows, show open panel
            NSDocumentController.shared.openDocument(nil)
        }
        return true
    }

    // MARK: - Auxiliary Windows

    @objc private func handleOpenAuxiliaryWindow(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let windowID = userInfo["windowID"] as? String,
              let viewModel = userInfo["viewModel"] as? CDFViewModel else {
            return
        }

        let viewModelID = ObjectIdentifier(viewModel)

        switch windowID {
        case "Time Series Chart":
            openChartWindow(for: viewModel, id: viewModelID)
        case "3D Globe":
            openGlobeWindow(for: viewModel, id: viewModelID)
        default:
            break
        }
    }

    private func openChartWindow(for viewModel: CDFViewModel, id: ObjectIdentifier) {
        // If window exists, bring to front
        if let existing = chartWindows[id], existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let chartView = TimeSeriesChartView(viewModel: viewModel)
        let hostingController = NSHostingController(rootView: chartView)

        let window = NSWindow(contentViewController: hostingController)
        window.setContentSize(NSSize(width: 900, height: 600))
        window.minSize = NSSize(width: 400, height: 300)
        window.title = "Time Series Chart"
        window.styleMask.insert(.fullSizeContentView)
        window.toolbarStyle = .unified
        configureToolbar(for: window, identifier: "ChartToolbar")

        window.makeKeyAndOrderFront(nil)
        chartWindows[id] = window
    }

    private func openGlobeWindow(for viewModel: CDFViewModel, id: ObjectIdentifier) {
        // If window exists, bring to front
        if let existing = globeWindows[id], existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let globeView = GlobeView(viewModel: viewModel)
        let hostingController = NSHostingController(rootView: globeView)

        let window = NSWindow(contentViewController: hostingController)
        window.setContentSize(NSSize(width: 900, height: 700))
        window.minSize = NSSize(width: 400, height: 300)
        window.title = "3D Globe"
        window.styleMask.insert(.fullSizeContentView)
        window.toolbarStyle = .unified
        window.backgroundColor = .black
        window.titlebarAppearsTransparent = true
        configureToolbar(for: window, identifier: "GlobeToolbar")

        window.makeKeyAndOrderFront(nil)
        globeWindows[id] = window
    }

    /// Configure an empty toolbar for Liquid Glass title bar integration
    private func configureToolbar(for window: NSWindow, identifier: String) {
        let toolbar = NSToolbar(identifier: identifier)
        toolbar.displayMode = .iconOnly
        toolbar.showsBaselineSeparator = false
        window.toolbar = toolbar
    }
}
