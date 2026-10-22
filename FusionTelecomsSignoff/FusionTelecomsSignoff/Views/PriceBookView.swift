import SwiftUI

struct PriceBookView: View {
    @EnvironmentObject var store: WorkOrderStore

    @State private var query = ""
    @State private var items: [PriceBookItem] = []
    @State private var loading = false
    @State private var loadedOnce = false
    @State private var errorMessage: String?

    private var errorBinding: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Price Book")
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(.visible, for: .navigationBar)
                .toolbarBackground(Color.brandPink, for: .navigationBar)
                .toolbarColorScheme(.dark, for: .navigationBar)
                .searchable(text: $query, prompt: "Search products")
                .onSubmit(of: .search) { Task { await load() } }
                .refreshable { await load() }
                .task { if !loadedOnce { await load() } }
                .alert("Couldn't load prices", isPresented: errorBinding) {
                    Button("OK", role: .cancel) { errorMessage = nil }
                } message: {
                    Text(errorMessage ?? "")
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        if items.isEmpty {
            emptyState
        } else {
            List(items) { PriceRow(item: $0) }
                .listStyle(.insetGrouped)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            if loading {
                ProgressView()
            } else {
                Image(systemName: "sterlingsign.circle")
                    .font(.system(size: 52))
                    .foregroundStyle(Color.brandPink.opacity(0.7))
                Text(query.isEmpty ? "Search the Quote Builder price book."
                                   : "No products match \u{201C}\(query)\u{201D}.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
    }

    private func load() async {
        guard !store.signoffAPIURL.isEmpty, !store.signoffAPIKey.isEmpty else {
            errorMessage = "Set your server URL and API key in Settings first."
            return
        }
        loading = true
        defer { loading = false; loadedOnce = true }
        do {
            items = try await QuoteBuilderAPI.searchPriceBook(
                query: query.trimmingCharacters(in: .whitespaces),
                baseURL: store.signoffAPIURL,
                apiKey: store.signoffAPIKey
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct PriceRow: View {
    let item: PriceBookItem

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(item.name).font(.headline)
                if let brand = item.brand, !brand.isEmpty {
                    Text(brand).font(.caption).foregroundStyle(.secondary)
                }
                if let sku = item.sku, !sku.isEmpty {
                    Text(sku).font(.caption2).foregroundStyle(.tertiary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(item.salePrice, format: .currency(code: "GBP"))
                    .font(.headline)
                    .foregroundStyle(Color.brandPink)
                Text(item.isMonthly ? "per month" : "one-off")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
