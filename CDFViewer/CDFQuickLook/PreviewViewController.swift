import Cocoa
import Quartz
import SwiftUI

/// QuickLook preview controller for CDF files
class PreviewViewController: NSViewController, QLPreviewingController {

    override var nibName: NSNib.Name? {
        return nil
    }

    override func loadView() {
        self.view = NSView()
    }

    func preparePreviewOfFile(at url: URL) async throws {
        // Parse the CDF file
        let reader = try CDFReader(url: url)
        try reader.parse()

        let fileInfo = reader.fileInfo()
        let variables = reader.variables
        let attributes = reader.attributes

        // Create the SwiftUI preview view
        let previewView = CDFPreviewView(
            fileInfo: fileInfo,
            variables: variables,
            attributes: attributes
        )

        // Host the SwiftUI view
        let hostingView = NSHostingView(rootView: previewView)
        hostingView.translatesAutoresizingMaskIntoConstraints = false

        await MainActor.run {
            view.addSubview(hostingView)
            NSLayoutConstraint.activate([
                hostingView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                hostingView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                hostingView.topAnchor.constraint(equalTo: view.topAnchor),
                hostingView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
            ])
        }
    }
}
