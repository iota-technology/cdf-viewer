import SwiftUI
import Sparkle

@main
struct CDFViewerApp: App {
    /// AppKit delegate for NSDocument handling
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    /// Sparkle updater controller
    private let updaterController = UpdaterController()

    var body: some Scene {
        // Welcome window shown when no documents are open
        WindowGroup(id: "welcome") {
            WelcomeView()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        .commands {
            // Replace default New Document with Open
            CommandGroup(replacing: .newItem) {
                Button("Open...") {
                    NSDocumentController.shared.openDocument(nil)
                }
                .keyboardShortcut("o", modifiers: .command)
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
