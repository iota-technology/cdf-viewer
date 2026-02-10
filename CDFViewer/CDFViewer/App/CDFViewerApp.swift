import SwiftUI
import UniformTypeIdentifiers

@main
struct CDFViewerApp: App {
    /// AppKit delegate for NSDocument handling
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // DocumentGroup is required for SwiftUI App lifecycle even though
        // actual windows are created by NSDocument.makeWindowControllers()
        DocumentGroup(viewing: CDFReferenceDocument.self) { _ in
            // This view is never shown - NSDocument handles window creation
            EmptyView()
        }
    }
}

/// Minimal FileDocument for SwiftUI DocumentGroup registration.
/// Actual file handling is done by CDFNSDocument.
struct CDFReferenceDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.cdf] }

    init(configuration: ReadConfiguration) throws {
        // Never actually called - CDFNSDocument handles file reading
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        throw CocoaError(.fileWriteNoPermission)
    }
}
