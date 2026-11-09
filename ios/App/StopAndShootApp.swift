import SwiftUI
import UniformTypeIdentifiers

@main
struct StopAndShootApp: App {
    @StateObject private var model = AppModel.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
                .onOpenURL { model.handle(url: $0) }
                .onChange(of: scenePhase) { _, phase in
                    model.setSceneActive(phase == .active)
                }
        }
    }
}

struct RootView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        NavigationStack {
            HomeView(model: model)
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .pin(let id):
                        PinDetailView(model: model, pinID: id)
                    case .help:
                        HelpView(model: model)
                    }
                }
        }
        .tint(Theme.orange)
        .preferredColorScheme(.dark)
        .fileImporter(isPresented: $model.importing, allowedContentTypes: [.json], onCompletion: model.importFile)
        .sheet(item: $model.shareFile) { item in
            ActivityView(items: [item.url])
        }
    }
}
