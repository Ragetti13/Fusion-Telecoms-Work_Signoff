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

                Section {
                    VStack(spacing: 6) {
                        Text("© \(Calendar.current.component(.year, from: Date())) Fusion Telecoms LTD")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Link("fusion-telecoms.com", destination: URL(string: "https://fusion-telecoms.com")!)
                            .font(.footnote)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                }
                .listRowBackground(Color.clear)
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
