import SwiftUI

struct ContentView: View {
    var body: some View {
        JobListView()
            // Keep a consistent bright, on-brand look on-site regardless of
            // the device's Light/Dark setting.
            .preferredColorScheme(.light)
    }
}
