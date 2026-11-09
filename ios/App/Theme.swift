import SwiftUI
import UIKit

enum Theme {
    static let bg = Color(red: 18 / 255, green: 22 / 255, blue: 30 / 255)
    static let card = Color(red: 32 / 255, green: 38 / 255, blue: 51 / 255)
    static let orange = Color(red: 1, green: 138 / 255, blue: 36 / 255)
    static let muted = Color(white: 0.72)
    static let warn = Color(red: 1, green: 0.78, blue: 0.45)
}

enum Route: Hashable {
    case pin(String)
    case help
}

struct ShareFile: Identifiable {
    let id = UUID()
    let url: URL
}

struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
