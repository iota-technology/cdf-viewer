import SwiftUI

@main
struct CDFViewerApp: App {
    /// AppKit delegate for NSDocument handling
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Empty Settings scene satisfies SwiftUI App requirement.
        // Actual document handling is done by NSDocument (CDFNSDocument).
        // Note: On older macOS this may show an empty Settings window on launch.
        Settings {
            EmptyView()
        }
    }
}
