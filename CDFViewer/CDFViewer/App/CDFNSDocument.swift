import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// NSDocument subclass for CDF files.
/// Using NSDocument instead of FileDocument to get access to the original file URL for xattr persistence.
class CDFNSDocument: NSDocument {

    /// The parsed CDF file data
    var cdfFile: CDFFile?

    /// Error encountered during loading (if any)
    var loadError: Error?

    /// View model for this document (shared with SwiftUI views)
    var viewModel = CDFViewModel()

    /// The original file URL (available from NSDocument.fileURL)
    var originalFileURL: URL? {
        fileURL
    }

    // MARK: - NSDocument Overrides

    override class var autosavesInPlace: Bool {
        false  // Read-only viewer
    }

    override func canAsynchronouslyWrite(to url: URL, ofType typeName: String, for saveOperation: NSDocument.SaveOperationType) -> Bool {
        false  // Read-only viewer
    }

    override class func canConcurrentlyReadDocuments(ofType typeName: String) -> Bool {
        true  // CDF files can be read concurrently
    }

    override func read(from url: URL, ofType typeName: String) throws {
        do {
            cdfFile = try CDFFile(url: url, displayName: url.lastPathComponent, options: .withUnixTimestamps)
            viewModel.cdfFile = cdfFile
            viewModel.originalFileURL = url
            viewModel.setupDefaults()

            // Load persisted metadata from xattr
            viewModel.loadMetadata()
        } catch {
            loadError = error
            Swift.print("CDF Load Error: \(error)")
            throw error
        }
    }

    override func makeWindowControllers() {
        // Add to recent documents list
        if let url = fileURL {
            NSDocumentController.shared.noteNewRecentDocumentURL(url)
        }

        // Create SwiftUI view hosted in NSHostingController
        let contentView = DocumentContentView(document: self)

        let hostingController = NSHostingController(rootView: contentView)

        let window = NSWindow(contentViewController: hostingController)
        window.setContentSize(NSSize(width: 1200, height: 800))
        window.minSize = NSSize(width: 600, height: 400)
        window.title = displayName
        window.styleMask.insert(.fullSizeContentView)
        window.titlebarAppearsTransparent = false
        window.toolbarStyle = .unified

        let windowController = NSWindowController(window: window)
        windowController.contentViewController = hostingController
        addWindowController(windowController)
    }

    // MARK: - Read-only (no writing support)

    override func data(ofType typeName: String) throws -> Data {
        throw CocoaError(.fileWriteNoPermission)
    }

    override func write(to url: URL, ofType typeName: String) throws {
        throw CocoaError(.fileWriteNoPermission)
    }

}

// MARK: - SwiftUI Bridge View

/// SwiftUI view that wraps the document content and provides environment
struct DocumentContentView: View {
    @ObservedObject var documentWrapper: DocumentWrapper
    @State private var showFileInfo = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @Environment(\.openWindow) private var openWindow

    init(document: CDFNSDocument) {
        self.documentWrapper = DocumentWrapper(document: document)
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            NavigationSidebarContainer {
                VariableListView(viewModel: documentWrapper.viewModel)
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 250, max: 350)
        } detail: {
            if documentWrapper.document.loadError != nil {
                ErrorView(error: documentWrapper.document.loadError!)
            } else {
                DataTableView(viewModel: documentWrapper.viewModel)
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    showFileInfo.toggle()
                } label: {
                    Label("File Info", systemImage: "info.circle")
                }
                .popover(isPresented: $showFileInfo) {
                    if let file = documentWrapper.document.cdfFile {
                        FileInfoView(fileInfo: file.fileInfo, attributes: file.attributes)
                            .frame(width: 400, height: 500)
                    }
                }

                Button {
                    openAuxiliaryWindow(id: "Time Series Chart")
                } label: {
                    Label("Chart", systemImage: "chart.xyaxis.line")
                }
                .disabled(documentWrapper.viewModel.chartTimeVariable == nil || documentWrapper.viewModel.isShowingConstants)
                .help(documentWrapper.viewModel.isShowingConstants ? "Chart requires a time-based independent variable" : "Open Time Series Chart")

                Button {
                    openAuxiliaryWindow(id: "3D Globe")
                } label: {
                    Label("Globe", systemImage: "globe")
                }
                .disabled(documentWrapper.document.cdfFile?.ecefPositionVariables().isEmpty ?? true || documentWrapper.viewModel.isShowingConstants)
                .help(documentWrapper.viewModel.isShowingConstants ? "Globe requires a time-based independent variable" : "Open 3D Globe")
            }
        }
        .navigationTitle(documentWrapper.document.cdfFile?.fileName ?? "CDF Viewer")
        .toolbarBackground(.hidden, for: .windowToolbar)
        .sidebarToggleToolbar()
        .toolbar(removing: .sidebarToggle)
    }

    private func openAuxiliaryWindow(id: String) {
        // Post notification to open auxiliary window with this document's viewModel
        NotificationCenter.default.post(
            name: .openAuxiliaryWindow,
            object: nil,
            userInfo: ["windowID": id, "viewModel": documentWrapper.viewModel]
        )
    }
}

/// Observable wrapper for NSDocument to work with SwiftUI
class DocumentWrapper: ObservableObject {
    let document: CDFNSDocument
    var viewModel: CDFViewModel { document.viewModel }

    init(document: CDFNSDocument) {
        self.document = document
    }
}

// MARK: - Notification for auxiliary windows

extension Notification.Name {
    static let openAuxiliaryWindow = Notification.Name("openAuxiliaryWindow")
}

