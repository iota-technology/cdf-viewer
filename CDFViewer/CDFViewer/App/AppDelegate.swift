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

    /// Welcome window managed programmatically (strong reference — we own it)
    private var welcomeWindow: NSWindow?

    /// About window
    private var aboutWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Register for auxiliary window notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleOpenAuxiliaryWindow(_:)),
            name: .openAuxiliaryWindow,
            object: nil
        )

        // Observe when windows become visible to close welcome window
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidBecomeKey(_:)),
            name: NSWindow.didBecomeKeyNotification,
            object: nil
        )

        // Observe when all document windows close to show welcome window
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowWillClose(_:)),
            name: NSWindow.willCloseNotification,
            object: nil
        )

        // Show welcome window after a delay to allow file-open events to arrive first.
        // When launched via double-clicking a file, the document opens before this fires.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.showWelcomeWindowIfNeeded()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        NotificationCenter.default.removeObserver(self)
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        false  // Don't create untitled documents - this is a viewer
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            // No visible windows, show welcome window
            showWelcomeWindowIfNeeded()
        }
        return true
    }

    // MARK: - Welcome Window Management

    @objc private func windowDidBecomeKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }

        // If a document window became key, hide the welcome window
        if window.windowController?.document is CDFNSDocument {
            closeWelcomeWindow()
        }
    }

    @objc private func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }

        // If a document window is closing, check if we need to quit the app
        if window.windowController?.document is CDFNSDocument {
            // Delay check to allow window to fully close
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.showWelcomeWindowIfNeeded()
            }
        }
    }

    private func createWelcomeWindow() {
        let hostingController = NSHostingController(rootView: WelcomeView())

        let window = NSWindow(contentViewController: hostingController)
        window.setContentSize(NSSize(width: 400, height: 340))
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.isExcludedFromWindowsMenu = true
        window.center()

        welcomeWindow = window
    }

    private func closeWelcomeWindow() {
        welcomeWindow?.orderOut(nil)
    }

    private func showWelcomeWindowIfNeeded() {
        // Check if any document windows are still open
        let hasDocumentWindows = NSDocumentController.shared.documents.contains { document in
            document.windowControllers.contains { $0.window?.isVisible == true }
        }

        if !hasDocumentWindows {
            if welcomeWindow == nil {
                createWelcomeWindow()
            }
            welcomeWindow?.makeKeyAndOrderFront(nil)
        }
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

        // Add empty toolbar so Liquid Glass effect is present from the start
        // (prevents jarring switch when SwiftUI toolbar items appear)
        let toolbar = NSToolbar(identifier: "ChartToolbar")
        toolbar.displayMode = .iconOnly
        window.toolbar = toolbar

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

        // Add empty toolbar so Liquid Glass effect is present from the start
        // (prevents jarring switch when SwiftUI toolbar items appear)
        let toolbar = NSToolbar(identifier: "GlobeToolbar")
        toolbar.displayMode = .iconOnly
        window.toolbar = toolbar

        window.makeKeyAndOrderFront(nil)
        globeWindows[id] = window
    }

    // MARK: - About Window

    @objc func showAboutWindow() {
        if let existing = aboutWindow, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let aboutView = AboutView()
        let hostingController = NSHostingController(rootView: aboutView)

        let window = NSPanel(contentViewController: hostingController)
        window.setContentSize(NSSize(width: 340, height: 320))
        window.styleMask = [.titled, .closable]
        window.title = "About CDF Viewer"
        window.isMovableByWindowBackground = true
        window.center()
        window.makeKeyAndOrderFront(nil)
        aboutWindow = window
    }
}

// MARK: - About View

/// Custom About view with clickable company links
struct AboutView: View {
    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    var body: some View {
        VStack(spacing: 16) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)

            Text("CDF Viewer")
                .font(.title)
                .fontWeight(.semibold)

            Text("Version \(version) (\(build))")
                .font(.callout)
                .foregroundStyle(.secondary)

            Text("View NASA Common Data Format files")
                .font(.callout)
                .foregroundStyle(.secondary)

            Divider()
                .padding(.horizontal, 32)

            VStack(spacing: 8) {
                HStack(spacing: 4) {
                    Text("Made")
                        .foregroundStyle(.secondary)
                    Link("byJP Limited", destination: URL(string: "https://byjp.biz")!)
                }

                HStack(spacing: 4) {
                    Text("for")
                        .foregroundStyle(.secondary)
                    Link("Iota Technology", destination: URL(string: "https://iotatechnology.com")!)
                }
            }
            .font(.callout)
        }
        .padding(32)
        .frame(width: 340, height: 320)
    }
}
