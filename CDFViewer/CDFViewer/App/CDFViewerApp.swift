import SwiftUI
import UniformTypeIdentifiers

@main
struct CDFViewerApp: App {
    /// Shared registry of view models by document ID for auxiliary windows
    @State private var viewModelRegistry = ViewModelRegistry()

    var body: some Scene {
        DocumentGroup(newDocument: CDFDocument()) { file in
            ContentView(document: file.$document)
                .environment(viewModelRegistry)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                // Remove "New" since we only open existing files
            }
        }

        // Chart window
        WindowGroup("Time Series Chart", id: "Time Series Chart", for: UUID.self) { $documentID in
            if let id = documentID, let viewModel = viewModelRegistry.viewModels[id] {
                TimeSeriesChartView(viewModel: viewModel)
            } else {
                ContentUnavailableView("No Data", systemImage: "chart.xyaxis.line", description: Text("Open a CDF file first"))
            }
        }
        .defaultSize(width: 900, height: 600)

        // Globe window
        WindowGroup("3D Globe", id: "3D Globe", for: UUID.self) { $documentID in
            if let id = documentID, let viewModel = viewModelRegistry.viewModels[id] {
                GlobeView(viewModel: viewModel)
            } else {
                ContentUnavailableView("No Data", systemImage: "globe", description: Text("Open a CDF file first"))
            }
        }
        .defaultSize(width: 900, height: 700)
    }
}

/// Registry to share view models between document windows and auxiliary windows
@Observable
final class ViewModelRegistry {
    var viewModels: [UUID: CDFViewModel] = [:]

    func register(_ viewModel: CDFViewModel, for id: UUID) {
        viewModels[id] = viewModel
    }

    func unregister(_ id: UUID) {
        viewModels.removeValue(forKey: id)
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
            cdfFile = try CDFFile(url: tempURL, displayName: filename)
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

