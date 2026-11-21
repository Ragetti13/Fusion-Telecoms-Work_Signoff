import SwiftUI

/// Quote detail: line items split one-off / monthly, totals, margin and the
/// contract terms. Drafts are fully editable — lines, contract, share link
/// and conversion to an order; converted quotes are read-only.
struct QuoteDetailView: View {
    @EnvironmentObject var store: WorkOrderStore
    let quote: QuoteListItem

    /// Freshest copy of the quote; the list row we navigated from goes stale
    /// as soon as a contract field is edited or the quote converts.
    @State private var current: QuoteListItem?
    @State private var summary: QuoteSummary?
    @State private var loading = false
    @State private var errorMessage: String?
    @State private var showingAddItem = false
    @State private var editingLine: QuoteLineItem?
    @State private var shareItems: [Any]?
    @State private var sharing = false
    @State private var showingConvert = false
    @State private var converting = false
    @State private var convertedOrderId: Int?
    @State private var upfrontText = ""

    private var q: QuoteListItem { current ?? quote }
    private var isDraft: Bool { q.isDraft }

    private var errorBinding: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }
    private var shareBinding: Binding<Bool> {
        Binding(get: { shareItems != nil }, set: { if !$0 { shareItems = nil } })
    }
    private var convertedBinding: Binding<Bool> {
        Binding(get: { convertedOrderId != nil }, set: { if !$0 { convertedOrderId = nil } })
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
            if isDraft {
                convertSection
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(q.customerName)
        .navigationBarTitleDisplayMode(.inline)
        .brandNavigationBar()
        .toolbar {
            if isDraft {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { Task { await shareQuote() } } label: {
                        Image(systemName: "square.and.arrow.up").foregroundStyle(.white)
                    }
                    .accessibilityLabel("Share quote link")
                    .disabled(sharing)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingAddItem = true } label: {
                        Image(systemName: "plus").foregroundStyle(.white)
                    }
                    .accessibilityLabel("Add product")
                }
            }
        }
        .sheet(isPresented: $showingAddItem) {
            ProductPickerSheet(quoteId: q.id) { await load() }
        }
        .sheet(item: $editingLine) { line in
            LineEditSheet(quoteId: q.id, line: line) { await load() }
        }
        .sheet(isPresented: shareBinding) {
            if let shareItems {
                ShareSheet(items: shareItems)
            }
        }
        .confirmationDialog("Convert this quote to an order?", isPresented: $showingConvert, titleVisibility: .visible) {
            Button("Convert to Order") { Task { await convert() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(convertPreviewText)
        }
        .alert("Converted to order", isPresented: convertedBinding) {
            Button("Share signing link") {
                let orderId = convertedOrderId
                convertedOrderId = nil
                if let orderId { Task { await shareOrder(orderId) } }
            }
            Button("Done", role: .cancel) { convertedOrderId = nil }
        } message: {
            Text("The customer signs via the link; sign-off unlocks once they have.")
        }
        .refreshable { await load() }
        .task { await load() }
        .alert("Something went wrong", isPresented: errorBinding) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var headerSection: some View {
        Section {
            LabeledContent("Status") {
                Text(isDraft ? "Draft" : "Converted")
                    .foregroundStyle(isDraft ? .orange : .green)
                    .fontWeight(.semibold)
            }
            if let ref = q.customerReference, !ref.isEmpty {
                LabeledContent("Reference", value: ref)
            }
            LabeledContent("Created", value: QuoteFormat.shortDate(q.createdAt))
            if isDraft {
                LabeledContent("Valid for", value: "\(q.validDays) days")
            }
            if q.acceptedAt != nil, isDraft {
                LabeledContent("Customer accepted") {
                    Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
                }
            }
        }
    }

    private static let contractPeriods = [1, 6, 12, 18, 24, 36]

    @ViewBuilder
    private var contractSection: some View {
        Section("Contract") {
            if isDraft {
                Picker("Type", selection: Binding(
                    get: { q.contractType ?? "none" },
                    set: { newType in Task { await setContractType(newType) } }
                )) {
                    Text("None").tag("none")
                    Text("Standard").tag("standard")
                    Text("Monthly").tag("monthly")
                    Text("Job").tag("job")
                }
                if let type = q.contractType, type != "job" {
                    Picker("Period", selection: Binding(
                        get: { q.contractPeriodMonths ?? 0 },
                        set: { months in
                            Task { await patchQuote(["contractPeriodMonths": months == 0 ? NSNull() : months]) }
                        }
                    )) {
                        Text("Not set").tag(0)
                        ForEach(Self.contractPeriods, id: \.self) { months in
                            Text("\(months) months").tag(months)
                        }
                    }
                }
                if q.contractType == "monthly" {
                    LabeledContent("Upfront %") {
                        TextField("e.g. 20", text: $upfrontText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 90)
                            .onSubmit { Task { await saveUpfront() } }
                    }
                    if upfrontText != upfrontSaved {
                        Button("Save upfront %") { Task { await saveUpfront() } }
                    }
                }
                Toggle("Renewal", isOn: Binding(
                    get: { q.isRenewal ?? false },
                    set: { value in Task { await patchQuote(["isRenewal": value]) } }
                ))
            } else if let type = q.contractType {
                LabeledContent("Type", value: contractLabel(type))
                if let months = q.contractPeriodMonths {
                    LabeledContent("Period", value: "\(months) months")
                }
                if let upfront = summary?.upfrontPaymentPercent {
                    LabeledContent("Upfront", value: "\(Int(upfront))% on signing")
                }
            } else {
                Text("No contract type selected.")
                    .foregroundStyle(.secondary)
            }
            if let value = q.termValue {
                LabeledContent("Value over term") {
                    Text(QuoteFormat.currency(value))
                        .fontWeight(.semibold)
                        .monospacedDigit()
                }
            }
        }
    }

    private var convertSection: some View {
        Section {
            Button {
                showingConvert = true
            } label: {
                HStack {
                    Spacer()
                    Text(converting ? "Converting…" : "Convert to Order")
                        .fontWeight(.semibold)
                    Image(systemName: "arrow.right")
                    Spacer()
                }
            }
            .disabled(converting || !canConvert)
        } footer: {
            if !canConvert {
                Text(q.contractType == nil
                     ? "Choose a contract type before converting."
                     : "Choose a contract period before converting.")
            }
        }
    }

    /// Mirrors the web rule: a type is required, and monthly needs a period.
    private var canConvert: Bool {
        guard let type = q.contractType else { return false }
        if type == "monthly" { return q.contractPeriodMonths != nil }
        return true
    }

    private var convertPreviewText: String {
        guard let summary else { return "" }
        if q.contractType == "monthly", let months = q.contractPeriodMonths {
            return "Monthly contract over \(months) months. One-off \(QuoteFormat.currency(summary.oneOffTotal)), recurring \(QuoteFormat.currency(summary.recurringTotal))/mo."
        }
        return "One-off \(QuoteFormat.currency(summary.oneOffTotal)), recurring \(QuoteFormat.currency(summary.recurringTotal))/mo."
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
                            if isDraft { editingLine = line }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            if isDraft {
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

    private func contractLabel(_ type: String) -> String {
        switch type {
        case "monthly": return "Monthly"
        case "job": return "Job"
        default: return "Standard"
        }
    }

    private var upfrontSaved: String {
        q.upfrontPaymentPercent.map { String(format: "%g", $0) } ?? ""
    }

    // MARK: actions

    @MainActor
    private func load() async {
        loading = true
        defer { loading = false }
        do {
            current = try await QuotesAPI.getQuote(id: quote.id, creds: store.quoteCredentials)
            summary = try await QuotesAPI.quoteSummary(id: quote.id, creds: store.quoteCredentials)
            upfrontText = upfrontSaved
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func patchQuote(_ fields: [String: Any?]) async {
        do {
            try await QuotesAPI.updateQuote(id: q.id, fields: fields, creds: store.quoteCredentials)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func setContractType(_ newType: String) async {
        // Clearing the type (or picking Job) drops the period, like the web.
        if newType == "none" {
            await patchQuote(["contractType": NSNull(), "contractPeriodMonths": NSNull()])
        } else if newType == "job" {
            await patchQuote(["contractType": newType, "contractPeriodMonths": NSNull()])
        } else {
            await patchQuote(["contractType": newType])
        }
    }

    @MainActor
    private func saveUpfront() async {
        let trimmed = upfrontText.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            await patchQuote(["upfrontPaymentPercent": NSNull()])
        } else if let pct = Double(trimmed.replacingOccurrences(of: ",", with: ".")), (0...100).contains(pct) {
            await patchQuote(["upfrontPaymentPercent": pct])
        } else {
            errorMessage = "Upfront must be a percentage between 0 and 100."
        }
    }

    @MainActor
    private func shareQuote() async {
        sharing = true
        defer { sharing = false }
        do {
            let url = try await QuotesAPI.shareQuoteURL(id: q.id, creds: store.quoteCredentials)
            shareItems = [url]
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func convert() async {
        guard let type = q.contractType else { return }
        converting = true
        defer { converting = false }
        do {
            let orderId = try await QuotesAPI.convertQuote(
                id: q.id, contractType: type,
                periodMonths: type == "job" ? nil : q.contractPeriodMonths,
                creds: store.quoteCredentials
            )
            await load()
            convertedOrderId = orderId
        } catch {
            // Cost-TBC and period validations surface verbatim.
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func shareOrder(_ orderId: Int) async {
        do {
            let url = try await QuotesAPI.shareOrderURL(orderId: orderId, creds: store.quoteCredentials)
            shareItems = [url]
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func deleteLine(_ line: QuoteLineItem) async {
        do {
            try await QuotesAPI.deleteLineItem(quoteId: q.id, lineItemId: line.id, creds: store.quoteCredentials)
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
