import SwiftUI

@main
struct CDFViewerApp: App {
    /// AppKit delegate for NSDocument handling
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Empty scene - windows are created by NSDocument.makeWindowControllers()
        Settings {
            EmptyView()
        }
    }
}
