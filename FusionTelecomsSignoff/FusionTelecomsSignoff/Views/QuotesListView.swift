import SwiftUI

enum QuoteFilter: String, CaseIterable, Identifiable {
    case all, draft, converted

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: return "All"
        case .draft: return "Draft"
        case .converted: return "Converted"
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
            }
            guard !query.isEmpty else { return true }
            let q = query.lowercased()
            return quote.customerName.lowercased().contains(q)
                || (quote.customerReference ?? "").lowercased().contains(q)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Status", selection: $filter) {
                    ForEach(QuoteFilter.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 8)

                content
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .brandNavigationBar()
            .toolbar { BrandLogoLeading() }
            .searchable(text: $query, prompt: "Search by customer or reference")
            .refreshable { await load() }
            .task { if !loadedOnce { await load() } }
            .alert("Couldn't load quotes", isPresented: errorBinding) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
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
                .font(.system(size: 52))
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
                    .font(.system(size: 52))
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
        if quote.isDraft {
            badge("Draft", color: .orange)
        } else {
            badge("Converted", color: .green)
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

extension QuoteListItem: Hashable {
    static func == (lhs: QuoteListItem, rhs: QuoteListItem) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
