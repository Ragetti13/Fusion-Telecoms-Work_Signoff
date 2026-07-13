import SwiftUI

@main
struct FusionTelecomsSignoffApp: App {
    @StateObject private var store = WorkOrderStore()

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
    }
}
