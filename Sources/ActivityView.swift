import SwiftUI
import UIKit

/// Wraps UIActivityViewController so we can share a generated file without
/// betting on ShareLink's Transferable overload resolution.
struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// Identifiable wrapper so the sheet can present a file URL.
struct ExportFile: Identifiable {
    let id = UUID()
    let url: URL
}
