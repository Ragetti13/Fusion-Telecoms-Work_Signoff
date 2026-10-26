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
            .onChange(of: category) { _ in Task { await load() } }
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
                category: category.apiValue,
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
