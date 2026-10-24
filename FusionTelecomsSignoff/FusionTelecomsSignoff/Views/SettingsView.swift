import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: WorkOrderStore
    @Environment(\.dismiss) var dismiss

    @State private var name = ""
    @State private var apiURL = ""
    @State private var apiKey = ""

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        return "Version \(v)"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 10) {
                        LogoBadge(size: 84, corner: 20)
                        Text("Field Ops")
                            .font(.headline)
                        Text(appVersion)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .listRowBackground(Color.clear)

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
                    Text("Jobs queued in Quote Builder are pulled down automatically when you open the app. The server address is pre-filled, and your key is stored securely and kept across app updates.")
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
            .brandNavigationBar()
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
