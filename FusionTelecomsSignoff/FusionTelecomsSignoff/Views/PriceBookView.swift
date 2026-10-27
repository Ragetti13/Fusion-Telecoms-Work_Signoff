import SwiftUI

enum PriceCategory: String, CaseIterable, Identifiable {
    case all
    case oneOff = "one_off"
    case monthly = "monthly_recurring"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: return "All"
        case .oneOff: return "One-off"
        case .monthly: return "Monthly"
        }
    }

    /// nil for "All" (no category filter sent to the server).
    var apiValue: String? { self == .all ? nil : rawValue }
}

struct PriceBookView: View {
    @EnvironmentObject var store: WorkOrderStore

    @State private var query = ""
    @State private var category: PriceCategory = .all
    @State private var items: [PriceBookItem] = []
    @State private var loading = false
    @State private var loadedOnce = false
    @State private var errorMessage: String?
    @State private var showingAdd = false
    // Set when the server was unreachable and results came from the local cache.
    @State private var usingCache = false
    @State private var cacheDate: Date?

    private var errorBinding: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Category", selection: $category) {
                    ForEach(PriceCategory.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 8)

                if usingCache {
                    offlineBanner
                }

                content
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .brandNavigationBar()
            .toolbar {
                BrandLogoLeading()
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingAdd = true } label: {
                        Image(systemName: "plus").foregroundStyle(.white)
                    }
                }
            }
            .searchable(text: $query, prompt: "Search products")
            .onSubmit(of: .search) { Task { await load() } }
            .onChange(of: category) { Task { await load() } }
            .refreshable { await load() }
            .task { if !loadedOnce { await load() } }
            .sheet(isPresented: $showingAdd) {
                AddProductView { Task { await load() } }
            }
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

    private var offlineBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "wifi.slash")
            Text(cacheDate.map { "Saved prices (offline) · updated \($0.formatted(date: .abbreviated, time: .shortened))" }
                 ?? "Saved prices (offline)")
                .font(.caption)
            Spacer()
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal)
        .padding(.bottom, 6)
    }

    private func load() async {
        guard !store.signoffAPIURL.isEmpty, !store.signoffAPIKey.isEmpty else {
            errorMessage = "Set your server URL and API key in Settings first."
            return
        }
        loading = true
        defer { loading = false; loadedOnce = true }
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        do {
            let results = try await QuoteBuilderAPI.searchPriceBook(
                query: trimmed,
                category: category.apiValue,
                baseURL: store.signoffAPIURL,
                apiKey: store.signoffAPIKey
            )
            items = results
            usingCache = false
            // Cache the full catalogue (unfiltered fetch) for offline use.
            if trimmed.isEmpty && category == .all {
                PriceBookCache.save(results)
            }
        } catch {
            // Offline / server down — fall back to the cached catalogue, filtered
            // locally, so the technician can still look prices up on site.
            if let cached = PriceBookCache.load() {
                items = PriceBookCache.filter(cached, query: trimmed, category: category)
                usingCache = true
                cacheDate = PriceBookCache.savedAt
            } else {
                errorMessage = "Couldn't reach the server and no saved prices are available yet. Open the Price Book once while online."
            }
        }
    }
}

/// Local cache of the full price book so lookups work with no signal.
enum PriceBookCache {
    private static let itemsKey = "PriceBookCacheItems"
    private static let dateKey = "PriceBookCacheSavedAt"

    static func save(_ items: [PriceBookItem]) {
        guard let data = try? JSONEncoder().encode(items) else { return }
        UserDefaults.standard.set(data, forKey: itemsKey)
        UserDefaults.standard.set(Date(), forKey: dateKey)
    }

    static func load() -> [PriceBookItem]? {
        guard let data = UserDefaults.standard.data(forKey: itemsKey),
              let items = try? JSONDecoder().decode([PriceBookItem].self, from: data)
        else { return nil }
        return items
    }

    static var savedAt: Date? {
        UserDefaults.standard.object(forKey: dateKey) as? Date
    }

    /// Filter the cached catalogue the way the server would (name/sku/brand,
    /// plus category), for offline search.
    static func filter(_ all: [PriceBookItem], query: String, category: PriceCategory) -> [PriceBookItem] {
        let q = query.lowercased()
        return all.filter { item in
            let matchesCategory = category == .all || item.category == category.rawValue
            let matchesQuery = q.isEmpty
                || item.name.lowercased().contains(q)
                || (item.sku?.lowercased().contains(q) ?? false)
                || (item.brand?.lowercased().contains(q) ?? false)
            return matchesCategory && matchesQuery
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

/// Add a new product to the Quote Builder catalogue from the app. Cost price is
/// set server-side (defaults to 0 for an admin to complete), so it isn't shown.
struct AddProductView: View {
    @EnvironmentObject var store: WorkOrderStore
    @Environment(\.dismiss) private var dismiss

    /// Called after a product is saved, so the list behind can refresh.
    let onSaved: () -> Void

    enum Category: String, CaseIterable, Identifiable {
        case oneOff = "one_off"
        case monthly = "monthly_recurring"
        var id: String { rawValue }
        var label: String { self == .oneOff ? "One-off" : "Monthly" }
    }

    @State private var name = ""
    @State private var category: Category = .oneOff
    @State private var priceText = ""
    @State private var sku = ""
    @State private var brand = ""
    @State private var details = ""
    @State private var termText = ""
    @State private var isHardware = false

    @State private var saving = false
    @State private var errorMessage: String?

    private var price: Double? { Double(priceText.replacingOccurrences(of: ",", with: ".")) }
    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && (price ?? -1) >= 0 && !saving
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Product name", text: $name)
                    Picker("Type", selection: $category) {
                        ForEach(Category.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    HStack {
                        Text("£")
                        TextField(category == .monthly ? "Price per month" : "Price", text: $priceText)
                            .keyboardType(.decimalPad)
                    }
                    if category == .monthly {
                        TextField("Minimum term (months)", text: $termText)
                            .keyboardType(.numberPad)
                    }
                } header: {
                    Text("Product")
                } footer: {
                    Text("Sale price only. The cost price is set in Quote Builder by the office.")
                }

                Section("Details (optional)") {
                    TextField("SKU", text: $sku)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                    TextField("Brand", text: $brand)
                    TextField("Description", text: $details, axis: .vertical)
                        .lineLimit(2...5)
                    Toggle("Hardware item", isOn: $isHardware)
                }

                Section {
                    Button { Task { await save() } } label: {
                        HStack {
                            if saving { ProgressView().tint(.white).padding(.trailing, 4) }
                            Text("Add to Price Book")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .disabled(!canSave)
                    .brandPrimaryButton()
                }
            }
            .navigationTitle("New Product")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(Color.brandPink, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert("Couldn't add product", isPresented: errorBinding) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func save() async {
        guard !store.signoffAPIURL.isEmpty, !store.signoffAPIKey.isEmpty else {
            errorMessage = "Set your server URL and API key in Settings first."
            return
        }
        guard let price else {
            errorMessage = "Enter a valid price."
            return
        }
        saving = true
        defer { saving = false }
        let product = ProductInput(
            name: name.trimmingCharacters(in: .whitespaces),
            salePrice: price,
            category: category.rawValue,
            sku: sku.trimmingCharacters(in: .whitespaces),
            brand: brand.trimmingCharacters(in: .whitespaces),
            description: details.trimmingCharacters(in: .whitespaces),
            minimumTermMonths: category == .monthly ? Int(termText) : nil,
            isHardware: isHardware
        )
        do {
            try await QuoteBuilderAPI.addProduct(product, baseURL: store.signoffAPIURL, apiKey: store.signoffAPIKey)
            onSaved()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
