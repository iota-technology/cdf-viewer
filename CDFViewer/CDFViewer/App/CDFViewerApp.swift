import SwiftUI

@main
struct CDFViewerApp: App {
    /// AppKit delegate for NSDocument handling
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

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

            Text("View NASA Common Data Format files")
                .foregroundStyle(.secondary)

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
