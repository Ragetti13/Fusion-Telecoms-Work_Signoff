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
        // Follows the device's Light/Dark setting.
    }
}
