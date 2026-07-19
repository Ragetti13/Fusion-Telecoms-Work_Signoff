import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: WorkOrderStore
    @Environment(\.dismiss) var dismiss

    @State private var name = ""
    @State private var apiURL = ""
    @State private var apiKey = ""

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
                    TextField("https://your-server.com", text: $apiURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("API Key", text: $apiKey)
                } header: {
                    Text("Quote Builder Sync")
                } footer: {
                    Text("Jobs queued in Quote Builder are pulled down automatically when you open the app.")
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
                        store.signoffAPIURL = apiURL.trimmingCharacters(in: .whitespaces)
                        store.signoffAPIKey = apiKey.trimmingCharacters(in: .whitespaces)
                        store.save()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .onAppear {
                name = store.technicianName
                apiURL = store.signoffAPIURL
                apiKey = store.signoffAPIKey
            }
        }
    }
}
