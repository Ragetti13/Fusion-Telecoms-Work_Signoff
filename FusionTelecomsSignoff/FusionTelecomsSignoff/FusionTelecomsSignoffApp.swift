import SwiftUI

@main
struct FusionTelecomsSignoffApp: App {
    @StateObject private var store = WorkOrderStore()
    @Environment(\.scenePhase) var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .onOpenURL { url in
                    if let prefill = DeepLinkHandler.parse(url: url) {
                        store.pendingPrefill = prefill
                    }
                }
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active {
                Task { await store.syncRemoteJobs() }
            }
        }
    }
}
