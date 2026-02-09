import SwiftUI
import UniformTypeIdentifiers

@main
struct CDFViewerApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: CDFDocument()) { file in
            ContentView(document: file.$document)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                // Remove "New" since we only open existing files
            }
        }
    }
}

// MARK: - CDF Document

struct CDFDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.cdf, .data] }

    var cdfFile: CDFFile?
    var loadError: Error?

    init() {
        // Empty document for new windows
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }

        // Write data to temp file and load (since CDFReader needs a file URL)
        let filename = configuration.file.filename ?? "document.cdf"
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + "_" + filename)

        do {
            try data.write(to: tempURL)
            cdfFile = try CDFFile(url: tempURL)
        } catch {
            loadError = error
            // Print error for debugging
            print("CDF Load Error: \(error)")
            throw error
        }
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        // Read-only viewer - no writing
        throw CocoaError(.fileWriteNoPermission)
    }
}

