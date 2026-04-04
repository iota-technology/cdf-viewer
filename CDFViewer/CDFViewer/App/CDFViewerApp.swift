import SwiftUI
import Sparkle

@main
struct CDFViewerApp: App {
    /// AppKit delegate for NSDocument handling
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    /// Sparkle updater controller
    private let updaterController = UpdaterController()

    var body: some Scene {
        // All windows are managed programmatically by AppDelegate / NSDocument.
        // We need a scene solely to host menu commands.
        // On macOS 15+ (Tahoe), Settings scenes auto-open on launch, so we
        // close the spurious window in AppDelegate.applicationDidFinishLaunching.
        Settings {
            EmptyView()
        }
        .commands {
            // Remove Settings menu item (no settings to show)
            CommandGroup(replacing: .appSettings) { }
            // Replace default New Document with Open + Open Recent
            CommandGroup(replacing: .newItem) {
                Button("Open...") {
                    NSDocumentController.shared.openDocument(nil)
                }
                .keyboardShortcut("o", modifiers: .command)

                OpenRecentMenu()
            }

            // Custom About with clickable links
            CommandGroup(replacing: .appInfo) {
                Button("About CDF Viewer") {
                    appDelegate.showAboutWindow()
                }
            }

            // Add Check for Updates to app menu
            CommandGroup(after: .appInfo) {
                Button("Check for Updates...") {
                    updaterController.checkForUpdates()
                }
                .disabled(!updaterController.canCheckForUpdates)
            }
        }
    }
}

// MARK: - Welcome View

/// Welcome screen shown when app launches with no documents
struct WelcomeView: View {
    var body: some View {
        VStack(spacing: 24) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 128, height: 128)

            Text("CDF Viewer")
                .font(.largeTitle)
                .fontWeight(.semibold)

            VStack(spacing: 4) {
                Text("View NASA Common Data Format files")
                    .foregroundStyle(.secondary)

                HStack(spacing: 4) {
                    Text("Made")
                        .foregroundStyle(.tertiary)
                    Link("byJP", destination: URL(string: "https://byjp.biz")!)
                        .opacity(0.7)
                    Text("for")
                        .foregroundStyle(.tertiary)
                    Link("Iota Technology", destination: URL(string: "https://iotatechnology.com")!)
                        .opacity(0.7)
                }
                .font(.caption)
            }

            Button(action: openFile) {
                Label("Open a CDF File", systemImage: "doc.badge.plus")
                    .frame(minWidth: 160)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
        }
        .padding(48)
        .frame(width: 400, height: 340)
    }

    private func openFile() {
        NSDocumentController.shared.openDocument(nil)
    }
}

// MARK: - Open Recent Menu

/// SwiftUI menu for recently opened documents
struct OpenRecentMenu: View {
    var body: some View {
        Menu("Open Recent") {
            let recentURLs = NSDocumentController.shared.recentDocumentURLs
            if recentURLs.isEmpty {
                Text("No Recent Items")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(recentURLs, id: \.self) { url in
                    Button(url.lastPathComponent) {
                        NSDocumentController.shared.openDocument(
                            withContentsOf: url,
                            display: true
                        ) { _, _, _ in }
                    }
                }

                Divider()

                Button("Clear Menu") {
                    NSDocumentController.shared.clearRecentDocuments(nil)
                }
            }
        }
    }
}
