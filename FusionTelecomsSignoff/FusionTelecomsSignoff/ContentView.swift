import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            JobListView()
                .tabItem { Label("Jobs", systemImage: "checkmark.seal") }
            LeadFormView()
                .tabItem { Label("New Lead", systemImage: "person.badge.plus") }
            PriceBookView()
                .tabItem { Label("Price Book", systemImage: "sterlingsign.circle") }
        }
        .tint(.brandPink)
        // Keep a consistent bright, on-brand look on-site regardless of the
        // device's Light/Dark setting.
        .preferredColorScheme(.light)
    }
}
