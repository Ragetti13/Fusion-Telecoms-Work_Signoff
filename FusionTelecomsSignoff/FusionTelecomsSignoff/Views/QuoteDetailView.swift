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
