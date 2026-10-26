import SwiftUI
import UIKit
import SafariServices

/// Identifiable wrapper so a URL can drive a `.sheet(item:)`.
struct QuoteLink: Identifiable {
    let id = UUID()
    let url: URL
}

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

    // Existing-customer check (Feature A)
    @State private var looking = false
    @State private var lookup: ContactLookupResult?

    // Quote pre-fill after a successful lead (Feature B)
    @State private var newQuoteURL: URL?
    @State private var quoteLink: QuoteLink?

    private var canSubmit: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && !submitting
    }

    private var canLookup: Bool {
        !looking && (!email.trimmingCharacters(in: .whitespaces).isEmpty
                     || !phone.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    private var resultBinding: Binding<Bool> {
        Binding(get: { resultMessage != nil }, set: { if !$0 { resultMessage = nil } })
    }

    var body: some View {
        NavigationStack {
            Form {
                leadSection
                contactSection
                lookupSection
                notesSection
                submitSection
                quoteSection
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { BrandLogoLeading() }
            .brandNavigationBar()
            .sheet(item: $quoteLink) { link in
                SafariView(url: link.url).ignoresSafeArea()
            }
            .alert(isError ? "Couldn't send lead" : "Lead sent", isPresented: resultBinding) {
                Button("OK", role: .cancel) { resultMessage = nil }
            } message: {
                Text(resultMessage ?? "")
            }
        }
    }

    // MARK: - Sections

    private var leadSection: some View {
        Section {
            TextField("Contact Name", text: $name)
            TextField("Company", text: $company)
        } header: {
            Text("Lead")
        } footer: {
            Text("Sent to Safe-Scale CRM as a new enquiry. Name is required.")
        }
    }

    private var contactSection: some View {
        Section("Contact") {
            TextField("Email", text: $email)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .onChange(of: email) { _ in lookup = nil }
            TextField("Phone", text: $phone)
                .keyboardType(.phonePad)
                .onChange(of: phone) { _ in lookup = nil }
            TextField("Address", text: $address, axis: .vertical)
                .lineLimit(2...4)
        }
    }

    @ViewBuilder
    private var lookupSection: some View {
        Section {
            Button { Task { await runLookup() } } label: {
                HStack {
                    if looking { ProgressView().padding(.trailing, 4) }
                    Label("Check CRM for existing customer", systemImage: "magnifyingglass")
                }
            }
            .disabled(!canLookup)

            if let lookup {
                if lookup.found, let contact = lookup.contact {
                    existingContactView(contact: contact, opportunities: lookup.opportunities)
                } else {
                    Label("No existing customer matches this email or phone.",
                          systemImage: "checkmark.circle")
                        .font(.subheadline)
                        .foregroundStyle(.green)
                }
            }
        } header: {
            Text("Duplicate Check")
        } footer: {
            Text("Searches Safe-Scale by email or phone before you create a new enquiry.")
        }
    }

    private var notesSection: some View {
        Section("Enquiry Notes") {
            TextField("What is the customer looking for?", text: $notes, axis: .vertical)
                .lineLimit(3...8)
        }
    }

    private var submitSection: some View {
        Section {
            Button { Task { await submit() } } label: {
                HStack {
                    if submitting { ProgressView().tint(.white).padding(.trailing, 4) }
                    Text("Send to CRM")
                }
                .frame(maxWidth: .infinity)
            }
            .disabled(!canSubmit)
            .brandPrimaryButton()
        }
    }

    @ViewBuilder
    private var quoteSection: some View {
        if let url = newQuoteURL {
            Section {
                Button { quoteLink = QuoteLink(url: url) } label: {
                    Label("Build a quote for this lead", systemImage: "doc.badge.plus")
                        .frame(maxWidth: .infinity)
                }
                .brandPrimaryButton()
            } footer: {
                Text("Opens Quote Builder with this customer pre-selected.")
            }
        }
    }

    @ViewBuilder
    private func existingContactView(contact: ContactSummary, opportunities: [ContactOpportunity]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Existing customer in CRM", systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline).fontWeight(.semibold)
                .foregroundStyle(Color.brandPink)
            Text(contact.name ?? "Unknown")
                .font(.headline)
            if let company = contact.companyName, !company.isEmpty {
                Text(company).font(.subheadline).foregroundStyle(.secondary)
            }
            if let e = contact.email, !e.isEmpty {
                Text(e).font(.caption).foregroundStyle(.tertiary)
            }
            if let p = contact.phone, !p.isEmpty {
                Text(p).font(.caption).foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)

        if opportunities.isEmpty {
            Text("No open opportunities on record.")
                .font(.caption).foregroundStyle(.secondary)
        } else {
            ForEach(opportunities) { opp in
                OpportunityRow(opp: opp)
            }
        }
    }

    // MARK: - Actions

    private func runLookup() async {
        guard !store.signoffAPIURL.isEmpty, !store.signoffAPIKey.isEmpty else {
            isError = true
            resultMessage = "Set your server URL and API key in Settings first."
            return
        }
        looking = true
        defer { looking = false }
        do {
            lookup = try await QuoteBuilderAPI.lookupContact(
                email: email.trimmingCharacters(in: .whitespaces),
                phone: phone.trimmingCharacters(in: .whitespaces),
                baseURL: store.signoffAPIURL,
                apiKey: store.signoffAPIKey
            )
        } catch {
            isError = true
            resultMessage = error.localizedDescription
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
            let result = try await QuoteBuilderAPI.submitLead(
                lead, baseURL: store.signoffAPIURL, apiKey: store.signoffAPIKey
            )
            isError = false
            resultMessage = "\(lead.name) was added to the CRM as a new enquiry."
            newQuoteURL = QuoteBuilderAPI.newQuoteURL(
                baseURL: store.signoffAPIURL, customerId: result.customerId
            )
            clearForm()
        } catch {
            isError = true
            resultMessage = error.localizedDescription
        }
    }

    private func clearForm() {
        name = ""; company = ""; email = ""; phone = ""; address = ""; notes = ""
        lookup = nil
    }
}

struct OpportunityRow: View {
    let opp: ContactOpportunity

    private var subtitle: String {
        [opp.pipelineName, opp.stageName].compactMap { $0 }.joined(separator: " · ")
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(opp.name).font(.subheadline)
                if !subtitle.isEmpty {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let status = opp.status, !status.isEmpty {
                Text(status.capitalized)
                    .font(.caption2).fontWeight(.semibold)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Color.brandPink.opacity(0.12))
                    .foregroundStyle(Color.brandPink)
                    .clipShape(Capsule())
            }
        }
        .padding(.vertical, 2)
    }
}

/// In-app Safari so "Build a quote" opens Quote Builder without leaving the app.
struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let config = SFSafariViewController.Configuration()
        config.barCollapsingEnabled = true
        let controller = SFSafariViewController(url: url, configuration: config)
        controller.preferredControlTintColor = UIColor(Color.brandPink)
        return controller
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}
