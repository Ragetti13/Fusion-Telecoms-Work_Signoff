import SwiftUI

/// Read-only quote detail: line items split one-off / monthly, totals, margin
/// and the contract terms — what you need in front of a customer. Editing
/// lands in a later phase.
struct QuoteDetailView: View {
    @EnvironmentObject var store: WorkOrderStore
    let quote: QuoteListItem

    @State private var summary: QuoteSummary?
    @State private var loading = false
    @State private var errorMessage: String?
    @State private var showingAddItem = false
    @State private var editingLine: QuoteLineItem?

    private var errorBinding: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }

    var body: some View {
        List {
            headerSection
            contractSection
            if let summary {
                lineSection(
                    title: "One-Off",
                    items: summary.lineItems.filter { !$0.isMonthly },
                    total: summary.oneOffTotal,
                    perMonth: false
                )
                lineSection(
                    title: "Monthly Recurring",
                    items: summary.lineItems.filter { $0.isMonthly },
                    total: summary.recurringTotal,
                    perMonth: true
                )
                totalsSection(summary)
            } else if loading {
                Section {
                    HStack { Spacer(); ProgressView(); Spacer() }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(quote.customerName)
        .navigationBarTitleDisplayMode(.inline)
        .brandNavigationBar()
        .toolbar {
            if quote.isDraft {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingAddItem = true } label: {
                        Image(systemName: "plus").foregroundStyle(.white)
                    }
                    .accessibilityLabel("Add product")
                }
            }
        }
        .sheet(isPresented: $showingAddItem) {
            ProductPickerSheet(quoteId: quote.id) { await load() }
        }
        .sheet(item: $editingLine) { line in
            LineEditSheet(quoteId: quote.id, line: line) { await load() }
        }
        .refreshable { await load() }
        .task { await load() }
        .alert("Couldn't load quote", isPresented: errorBinding) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var headerSection: some View {
        Section {
            LabeledContent("Status") {
                Text(quote.isDraft ? "Draft" : "Converted")
                    .foregroundStyle(quote.isDraft ? .orange : .green)
                    .fontWeight(.semibold)
            }
            if let ref = quote.customerReference, !ref.isEmpty {
                LabeledContent("Reference", value: ref)
            }
            LabeledContent("Created", value: QuoteFormat.shortDate(quote.createdAt))
            if quote.isDraft {
                LabeledContent("Valid for", value: "\(quote.validDays) days")
            }
            if quote.acceptedAt != nil, quote.isDraft {
                LabeledContent("Customer accepted") {
                    Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
                }
            }
        }
    }

    @ViewBuilder
    private var contractSection: some View {
        Section("Contract") {
            if let type = quote.contractType {
                LabeledContent("Type", value: contractLabel(type))
                if let months = quote.contractPeriodMonths {
                    LabeledContent("Period", value: "\(months) months")
                }
                if let upfront = summary?.upfrontPaymentPercent {
                    LabeledContent("Upfront", value: "\(Int(upfront))% on signing")
                }
                if let value = quote.termValue {
                    LabeledContent("Value over term") {
                        Text(QuoteFormat.currency(value))
                            .fontWeight(.semibold)
                            .monospacedDigit()
                    }
                }
            } else {
                Text("No contract type selected.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func lineSection(title: String, items: [QuoteLineItem], total: Double, perMonth: Bool) -> some View {
        Section {
            if items.isEmpty {
                Text("No \(title.lowercased()) items.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(items) { line in
                    QuoteLineRow(line: line, perMonth: perMonth)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if quote.isDraft { editingLine = line }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            if quote.isDraft {
                                Button(role: .destructive) {
                                    Task { await deleteLine(line) }
                                } label: {
                                    Label("Remove", systemImage: "trash")
                                }
                            }
                        }
                }
                HStack {
                    Text("Total").fontWeight(.semibold)
                    Spacer()
                    Text(QuoteFormat.currency(total) + (perMonth ? "/mo" : ""))
                        .fontWeight(.semibold)
                        .monospacedDigit()
                }
            }
        } header: {
            Text(title)
        }
    }

    private func totalsSection(_ summary: QuoteSummary) -> some View {
        Section("Totals") {
            LabeledContent("One-off", value: QuoteFormat.currency(summary.oneOffTotal))
            LabeledContent("Monthly", value: QuoteFormat.currency(summary.recurringTotal) + "/mo")
            if let upfront = summary.upfrontPayment {
                LabeledContent("Upfront payment", value: QuoteFormat.currency(upfront))
            }
            LabeledContent("Gross margin") {
                Text("\(summary.totalMarginPercent, specifier: "%.1f")% · \(QuoteFormat.currency(summary.totalMarginAmount))")
                    .foregroundStyle(summary.totalMarginAmount < 0 ? .red : .green)
                    .fontWeight(.semibold)
                    .monospacedDigit()
            }
        }
    }

    private func contractLabel(_ type: String) -> String {
        switch type {
        case "monthly": return "Monthly"
        case "job": return "Job"
        default: return "Standard"
        }
    }

    @MainActor
    private func load() async {
        loading = true
        defer { loading = false }
        do {
            summary = try await QuotesAPI.quoteSummary(id: quote.id, creds: store.quoteCredentials)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func deleteLine(_ line: QuoteLineItem) async {
        do {
            try await QuotesAPI.deleteLineItem(quoteId: quote.id, lineItemId: line.id, creds: store.quoteCredentials)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct QuoteLineRow: View {
    let line: QuoteLineItem
    let perMonth: Bool

    private var declined: Bool {
        (line.isOptional ?? false) && !(line.optionalSelected ?? false)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(line.productNameSnapshot)
                    .font(.subheadline.weight(.medium))
                    .strikethrough(declined)
                Spacer()
                Text(QuoteFormat.currency(line.lineTotal) + (perMonth ? "/mo" : ""))
                    .font(.subheadline.monospacedDigit())
                    .strikethrough(declined)
            }
            HStack(spacing: 8) {
                Text("\(Int(line.quantity)) × \(QuoteFormat.currency(line.unitSalePriceSnapshot))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let discount = line.discountAmount, discount > 0 {
                    Text("−\(QuoteFormat.currency(discount)) discount")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                if line.isOptional ?? false {
                    Text(declined ? "Optional — declined" : "Optional add-on")
                        .font(.caption)
                        .foregroundStyle(declined ? .secondary : Color.brandPink)
                }
            }
            if let desc = line.productDescriptionSnapshot, !desc.isEmpty {
                Text(desc)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 2)
        .opacity(declined ? 0.6 : 1)
    }
}

// MARK: - Add product

/// Search the price book and add a product to the draft quote.
struct ProductPickerSheet: View {
    @EnvironmentObject var store: WorkOrderStore
    @Environment(\.dismiss) var dismiss

    let quoteId: Int
    /// Runs after a successful add so the detail view can reload.
    let onAdded: () async -> Void

    @State private var query = ""
    @State private var category: PriceCategory = .all
    @State private var items: [PriceBookItem] = []
    @State private var loading = false
    @State private var selected: PriceBookItem?
    @State private var quantity = 1
    @State private var isOptional = false
    @State private var saving = false
    @State private var errorMessage: String?

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

                if let selected {
                    selectedBar(selected)
                }

                List(items) { item in
                    Button {
                        selected = item
                        quantity = 1
                        isOptional = false
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(.primary)
                                if let sku = item.sku, !sku.isEmpty {
                                    Text(sku).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Text(QuoteFormat.currency(item.salePrice) + (item.isMonthly ? "/mo" : ""))
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .overlay {
                    if items.isEmpty {
                        if loading {
                            ProgressView()
                        } else {
                            Text(query.isEmpty ? "Search the price book." : "No products match.")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Add Product")
            .navigationBarTitleDisplayMode(.inline)
            .brandNavigationBar()
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .searchable(text: $query, prompt: "Search products")
            .onSubmit(of: .search) { Task { await search() } }
            .onChange(of: category) { Task { await search() } }
            .task { await search() }
            .alert("Couldn't add product", isPresented: errorBinding) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func selectedBar(_ item: PriceBookItem) -> some View {
        VStack(spacing: 10) {
            HStack {
                Text(item.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                Spacer()
                Button { selected = nil } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
            }
            HStack {
                Stepper("Qty: \(quantity)", value: $quantity, in: 1...999)
                    .fixedSize()
                Spacer()
                Toggle("Optional", isOn: $isOptional)
                    .toggleStyle(.button)
            }
            Button {
                Task { await add(item) }
            } label: {
                Text(saving ? "Adding…" : "Add \(quantity) × \(item.name)")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.brandPink)
            .disabled(saving)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
    }

    @MainActor
    private func search() async {
        loading = true
        defer { loading = false }
        do {
            items = try await QuoteBuilderAPI.searchPriceBook(
                query: query, category: category.apiValue,
                baseURL: store.signoffAPIURL, apiKey: store.signoffAPIKey
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func add(_ item: PriceBookItem) async {
        saving = true
        defer { saving = false }
        do {
            try await QuotesAPI.addLineItem(
                quoteId: quoteId, productId: item.id, quantity: quantity,
                isOptional: isOptional, creds: store.quoteCredentials
            )
            dismiss()
            await onAdded()
        } catch {
            // Minimum-term and other server rules surface here verbatim.
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Edit line

/// Edit a draft line: quantity, unit price, discount and the optional flag.
/// The server enforces the pricing rules (e.g. never selling below cost) and
/// its refusal message is shown verbatim.
struct LineEditSheet: View {
    @EnvironmentObject var store: WorkOrderStore
    @Environment(\.dismiss) var dismiss

    let quoteId: Int
    let line: QuoteLineItem
    let onSaved: () async -> Void

    @State private var quantity: Int = 1
    @State private var priceText = ""
    @State private var discountKind = "none"      // "none" | "percent" | "amount"
    @State private var discountText = ""
    @State private var optional = false
    @State private var saving = false
    @State private var errorMessage: String?

    private var errorBinding: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(line.productNameSnapshot) {
                    Stepper("Quantity: \(quantity)", value: $quantity, in: 1...999)
                    LabeledContent("Unit price") {
                        TextField("0.00", text: $priceText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 110)
                    }
                    Toggle("Optional add-on", isOn: $optional)
                }

                Section("Discount") {
                    Picker("Type", selection: $discountKind) {
                        Text("None").tag("none")
                        Text("Percent").tag("percent")
                        Text("Amount").tag("amount")
                    }
                    .pickerStyle(.segmented)
                    if discountKind != "none" {
                        LabeledContent(discountKind == "percent" ? "Percent off" : "Amount off") {
                            TextField("0", text: $discountText)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 110)
                        }
                    }
                }
            }
            .navigationTitle("Edit Line")
            .navigationBarTitleDisplayMode(.inline)
            .brandNavigationBar()
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(saving ? "Saving…" : "Save") { Task { await save() } }
                        .fontWeight(.semibold)
                        .disabled(saving)
                }
            }
            .onAppear {
                quantity = Int(line.quantity)
                priceText = String(format: "%.2f", line.unitSalePriceSnapshot)
                optional = line.isOptional ?? false
                if let type = line.discountType, let value = line.discountValue {
                    discountKind = type
                    discountText = type == "percent"
                        ? String(format: "%g", value)
                        : String(format: "%.2f", value)
                }
            }
            .alert("Couldn't save", isPresented: errorBinding) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    @MainActor
    private func save() async {
        saving = true
        defer { saving = false }
        var fields: [String: Any?] = [
            "quantity": quantity,
            "isOptional": optional,
        ]
        if let price = Double(priceText.replacingOccurrences(of: ",", with: ".")) {
            fields["unitSalePrice"] = price
        }
        if discountKind == "none" {
            fields["discountType"] = NSNull()
            fields["discountValue"] = NSNull()
        } else if let value = Double(discountText.replacingOccurrences(of: ",", with: ".")), value > 0 {
            fields["discountType"] = discountKind
            fields["discountValue"] = value
        }
        do {
            try await QuotesAPI.updateLineItem(
                quoteId: quoteId, lineItemId: line.id, fields: fields,
                creds: store.quoteCredentials
            )
            dismiss()
            await onSaved()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
