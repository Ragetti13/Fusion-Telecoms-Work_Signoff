import SwiftUI

struct LeadFormView: View {
    @EnvironmentObject var store: WorkOrderStore

    @State private var name = ""
    @State private var company = ""
    @State private var email = ""
    @State private var phone = ""
    @State private var address = ""
    @State private var notes = ""
    @State private var submitting = false
    @State private var resultMessage: String?
    @State private var isError = false

    private var canSubmit: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && !submitting
    }

    private var resultBinding: Binding<Bool> {
        Binding(get: { resultMessage != nil }, set: { if !$0 { resultMessage = nil } })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Contact Name", text: $name)
                    TextField("Company", text: $company)
                } header: {
                    Text("Lead")
                } footer: {
                    Text("Sent to Safe-Scale CRM as a new enquiry. Name is required.")
                }

                Section("Contact") {
                    TextField("Email", text: $email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Phone", text: $phone)
                        .keyboardType(.phonePad)
                    TextField("Address", text: $address, axis: .vertical)
                        .lineLimit(2...4)
                }

                Section("Enquiry Notes") {
                    TextField("What is the customer looking for?", text: $notes, axis: .vertical)
                        .lineLimit(3...8)
                }

                Section {
                    Button { Task { await submit() } } label: {
                        HStack {
                            if submitting { ProgressView().padding(.trailing, 4) }
                            Text("Send to CRM")
                        }
                    }
                    .disabled(!canSubmit)
                    .fontWeight(.semibold)
                }
            }
            .navigationTitle("New Lead")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(Color.brandPink, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .alert(isError ? "Couldn't send lead" : "Lead sent", isPresented: resultBinding) {
                Button("OK", role: .cancel) {
                    if !isError { clearForm() }
                    resultMessage = nil
                }
            } message: {
                Text(resultMessage ?? "")
            }
        }
    }

    private func submit() async {
        guard !store.signoffAPIURL.isEmpty, !store.signoffAPIKey.isEmpty else {
            isError = true
            resultMessage = "Set your server URL and API key in Settings first."
            return
        }
        submitting = true
        defer { submitting = false }
        let lead = LeadInput(
            name: name.trimmingCharacters(in: .whitespaces),
            companyName: company.trimmingCharacters(in: .whitespaces),
            email: email.trimmingCharacters(in: .whitespaces),
            phone: phone.trimmingCharacters(in: .whitespaces),
            address: address.trimmingCharacters(in: .whitespaces),
            notes: notes.trimmingCharacters(in: .whitespaces)
        )
        do {
            try await QuoteBuilderAPI.submitLead(lead, baseURL: store.signoffAPIURL, apiKey: store.signoffAPIKey)
            isError = false
            resultMessage = "\(lead.name) was added to the CRM as a new enquiry."
        } catch {
            isError = true
            resultMessage = error.localizedDescription
        }
    }

    private func clearForm() {
        name = ""; company = ""; email = ""; phone = ""; address = ""; notes = ""
    }
}
