import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            Tab("Jobs", systemImage: "checkmark.seal") {
                JobListView()
            }
            Tab("New Lead", systemImage: "person.badge.plus") {
                LeadFormView()
            }
            Tab("Price Book", systemImage: "sterlingsign.circle") {
                PriceBookView()
            }
        }
        // On a regular-width display — the iPhone Duo inner display reports
        // regular horizontal *and* vertical size classes, as does iPad — the
        // tab bar becomes a sidebar instead of a stretched phone tab bar.
        .tabViewStyle(.sidebarAdaptable)
        .tint(.brandPink)
        // Follows the device's Light/Dark setting.
    }
}
