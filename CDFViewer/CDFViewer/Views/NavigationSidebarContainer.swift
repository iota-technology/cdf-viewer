import SwiftUI

/// Unified sidebar container for NavigationSplitView.
///
/// This component provides consistent sidebar styling across all views (Table, Chart, Globe).
/// Use `sidebarToggleToolbar()` modifier on NavigationSplitView to add a left-aligned toggle button.
///
/// Usage:
/// ```swift
/// NavigationSplitView(columnVisibility: $columnVisibility) {
///     NavigationSidebarContainer(sidebarBackground: .black /* optional */) {
///         sidebarView
///     }
/// } detail: {
///     detailView
/// }
/// .sidebarToggleToolbar()
/// .toolbar(removing: .sidebarToggle)  // Remove SwiftUI's default (right-aligned) toggle
/// .toolbarBackground(.hidden, for: .windowToolbar)
/// ```
struct NavigationSidebarContainer<Content: View>: View {
    var sidebarBackground: Color? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .modifier(SidebarBackgroundModifier(background: sidebarBackground))
    }
}

/// Applies optional background color to sidebar
private struct SidebarBackgroundModifier: ViewModifier {
    let background: Color?

    func body(content: Content) -> some View {
        if let bg = background {
            content
                .scrollContentBackground(.hidden)
                .background(bg)
        } else {
            content
        }
    }
}

// MARK: - Sidebar Toggle Toolbar

/// Adds a left-aligned sidebar toggle button to the toolbar.
/// This uses the native NSSplitViewController.toggleSidebar action for proper macOS integration.
struct SidebarToggleToolbarModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    Button {
                        toggleSidebar()
                    } label: {
                        Image(systemName: "sidebar.leading")
                    }
                    .help("Toggle Sidebar")
                }
            }
    }

    private func toggleSidebar() {
        #if os(macOS)
        // Use sendAction to nil which searches the entire responder chain
        // This works even when SceneView or other views capture first responder
        NSApp.sendAction(
            #selector(NSSplitViewController.toggleSidebar(_:)),
            to: nil,
            from: nil
        )
        #endif
    }
}

extension View {
    /// Adds a left-aligned sidebar toggle button that works with NavigationSplitView.
    /// Use with `.toolbar(removing: .sidebarToggle)` to remove SwiftUI's default right-aligned toggle.
    func sidebarToggleToolbar() -> some View {
        modifier(SidebarToggleToolbarModifier())
    }
}
