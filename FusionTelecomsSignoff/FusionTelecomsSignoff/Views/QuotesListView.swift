import SwiftUI

enum QuoteFilter: String, CaseIterable, Identifiable {
    case all, draft, converted, closed

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: return "All"
        case .draft: return "Draft"
        case .converted: return "Converted"
        case .closed: return "Closed"
        }
    }
}

/// Browse the Quote Builder quotes: search, status filter, values over the
/// contract term — the native counterpart of the web tool's quotes list.
struct QuotesListView: View {
    @EnvironmentObject var store: WorkOrderStore

    @State private var quotes: [QuoteListItem] = []
    @State private var query = ""
    @State private var filter: QuoteFilter = .all
    @State private var loading = false
    @State private var loadedOnce = false
    @State private var errorMessage: String?
    @State private var showingNewQuote = false
    @State private var path: [QuoteListItem] = []
    /// Scales the empty-state glyphs with the message beneath them, matching
    /// the pattern in PriceBookView and JobSummaryCard.
    @ScaledMetric(relativeTo: .largeTitle) private var emptyStateIcon: CGFloat = 52

    private var errorBinding: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }

    private var needsSignIn: Bool {
        store.quoteUsername.isEmpty || store.quotePassword.isEmpty
    }

    private var visible: [QuoteListItem] {
        quotes.filter { quote in
            switch filter {
            case .all: break
            case .draft:
                guard quote.isDraft, !quote.isSuperseded else { return false }
            case .converted:
                guard quote.status == "converted", !quote.isSuperseded else { return false }
            case .closed:
                guard quote.isClosed, !quote.isSuperseded else { return false }
            }
            guard !query.isEmpty else { return true }
            let q = query.lowercased()
            return quote.customerName.lowercased().contains(q)
                || (quote.customerReference ?? "").lowercased().contains(q)
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                Picker("Status", selection: $filter) {
                    ForEach(QuoteFilter.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 8)

                content
            }
            // A real title, not "": the back button on a pushed quote takes
            // its label from here, and VoiceOver had no name for the screen.
            // The logo still carries the branding from the leading slot.
            .navigationTitle("Quotes")
            .navigationBarTitleDisplayMode(.inline)
            .brandNavigationBar()
            .toolbar {
                BrandLogoLeading()
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingNewQuote = true } label: {
                        Image(systemName: "plus").foregroundStyle(.white)
                    }
                    .accessibilityLabel("New quote")
                    .disabled(needsSignIn)
                }
            }
            .searchable(text: $query, prompt: "Search by customer or reference")
            .refreshable { await load() }
            .task { if !loadedOnce { await load() } }
            .alert("Couldn't load quotes", isPresented: errorBinding) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
            .sheet(isPresented: $showingNewQuote) {
                NewQuoteSheet { newId in
                    await load()
                    if let fresh = quotes.first(where: { $0.id == newId }) {
                        path.append(fresh)
                    }
                }
            }
            .navigationDestination(for: QuoteListItem.self) { quote in
                QuoteDetailView(quote: quote)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if needsSignIn {
            signInPrompt
        } else if visible.isEmpty {
            emptyState
        } else {
            List(visible) { quote in
                NavigationLink(value: quote) {
                    QuoteRow(quote: quote)
                }
            }
            .listStyle(.insetGrouped)
        }
    }

    private var signInPrompt: some View {
        VStack(spacing: 14) {
            Image(systemName: "person.badge.key")
                .font(.system(size: emptyStateIcon))
                .foregroundStyle(Color.brandPink.opacity(0.7))
            Text("Add your Quote Builder username and password in Settings to browse quotes.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            if loading {
                ProgressView()
            } else {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: emptyStateIcon))
                    .foregroundStyle(Color.brandPink.opacity(0.7))
                Text(query.isEmpty ? "No quotes yet." : "No quotes match \u{201C}\(query)\u{201D}.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    @MainActor
    private func load() async {
        guard !needsSignIn else { return }
        loading = true
        defer { loading = false; loadedOnce = true }
        do {
            // Newest first, matching the web tool.
            quotes = try await QuotesAPI.listQuotes(creds: store.quoteCredentials).reversed()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct QuoteRow: View {
    let quote: QuoteListItem

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(quote.customerName)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                Text(QuoteFormat.currency(quote.termValue ?? 0))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 6) {
                statusBadge
                if quote.isSuperseded {
                    badge("Superseded", color: .gray)
                }
                if quote.acceptedAt != nil, quote.isDraft {
                    badge("Accepted", color: .green)
                }
                if let ref = quote.customerReference, !ref.isEmpty {
                    Text(ref)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Text(QuoteFormat.shortDate(quote.createdAt))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch quote.status {
        case "draft": badge("Draft", color: .orange)
        case "declined": badge("Declined", color: .red)
        case "lost": badge("Lost", color: .gray)
        default: badge("Converted", color: .green)
        }
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }
}

/// Start a draft quote: customer name (free text) plus an optional reference.
/// Linking to an existing customer record stays on the web for now.
struct NewQuoteSheet: View {
    @EnvironmentObject var store: WorkOrderStore
    @Environment(\.dismiss) var dismiss

    /// Runs after a successful create, with the new quote's id.
    let onCreated: (Int) async -> Void

    @State private var customerName = ""
    @State private var reference = ""
    @State private var saving = false
    @State private var errorMessage: String?

    @State private var confirmDiscard = false

    private var errorBinding: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }

    private var isDirty: Bool {
        !customerName.trimmingCharacters(in: .whitespaces).isEmpty || !reference.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Customer name", text: $customerName)
                        .submitLabel(.done)
                    TextField("Reference (optional)", text: $reference)
                        .textInputAutocapitalization(.characters)
                        .submitLabel(.done)
                } footer: {
                    Text("Creates a draft quote you can add products to straight away.")
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("New Quote")
            .navigationBarTitleDisplayMode(.inline)
            .brandNavigationBar()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if isDirty { confirmDiscard = true } else { dismiss() }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if saving {
                        ProgressView().tint(.white)
                    } else {
                        Button("Create") { Task { await create() } }
                            .fontWeight(.semibold)
                            .disabled(customerName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            // A sheet with typed-in content shouldn't vanish on a stray swipe.
            .interactiveDismissDisabled(isDirty)
            .confirmationDialog("Discard this quote?", isPresented: $confirmDiscard, titleVisibility: .visible) {
                Button("Discard", role: .destructive) { dismiss() }
                Button("Keep Editing", role: .cancel) {}
            }
            .alert("Couldn't create quote", isPresented: errorBinding) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    @MainActor
    private func create() async {
        saving = true
        defer { saving = false }
        do {
            let id = try await QuotesAPI.createQuote(
                customerName: customerName.trimmingCharacters(in: .whitespaces),
                reference: reference.trimmingCharacters(in: .whitespaces),
                creds: store.quoteCredentials
            )
            dismiss()
            await onCreated(id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

extension QuoteListItem: Hashable {
    static func == (lhs: QuoteListItem, rhs: QuoteListItem) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
