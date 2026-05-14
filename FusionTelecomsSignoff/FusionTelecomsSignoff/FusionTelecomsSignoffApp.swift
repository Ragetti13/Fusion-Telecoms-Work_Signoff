import SwiftUI

@main
struct FusionTelecomsSignoffApp: App {
    @StateObject private var store = WorkOrderStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
        }
    }
}
