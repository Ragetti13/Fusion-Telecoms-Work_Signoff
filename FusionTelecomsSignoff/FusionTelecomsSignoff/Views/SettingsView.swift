import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: WorkOrderStore
    @Environment(\.dismiss) var dismiss

    @State private var name = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Your Name / Technician Name", text: $name)
                } header: {
                    Text("Your Details")
                } footer: {
                    Text("This name appears on work orders and exported PDFs.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        store.technicianName = name.trimmingCharacters(in: .whitespaces)
                        store.save()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .onAppear {
                name = store.technicianName
            }
        }
    }
}
