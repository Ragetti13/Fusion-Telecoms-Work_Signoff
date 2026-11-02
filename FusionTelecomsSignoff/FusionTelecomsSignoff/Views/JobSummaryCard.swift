import SwiftUI

struct JobSummaryCard: View {
    let workOrder: WorkOrder

    /// Apple Maps directions to the site address.
    private var directionsURL: URL? {
        let address = workOrder.customerAddress.trimmingCharacters(in: .whitespaces)
        guard !address.isEmpty,
              let encoded = address.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
        else { return nil }
        return URL(string: "https://maps.apple.com/?daddr=\(encoded)")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Layout.gap) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    if !workOrder.jobReference.isEmpty {
                        Text(workOrder.jobReference)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text("Work Completion Summary")
                        .font(.headline)
                }
                Spacer()
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.title2)
                    .foregroundStyle(Color.brandPink)
                    .accessibilityHidden(true)
            }

            Divider()

            DetailRow(label: "Customer", value: workOrder.customerName)

            if !workOrder.customerAddress.isEmpty {
                DetailRow(label: "Address", value: workOrder.customerAddress)
                if let url = directionsURL {
                    // Previously nudged across with a hardcoded 85pt leading
                    // pad to line up with the value column; it now sits on its
                    // own row so it can't drift out of alignment.
                    Link(destination: url) {
                        Label("Directions", systemImage: "map.fill")
                            .font(.subheadline).fontWeight(.semibold)
                    }
                    .buttonStyle(.bordered)
                    .tint(.brandPink)
                    .accessibilityLabel("Directions to \(workOrder.customerAddress)")
                }
            }

            DetailRow(label: "Date", value: workOrder.completedDate.formatted(date: .long, time: .shortened))

            if !workOrder.technicianName.isEmpty {
                DetailRow(label: "Technician", value: workOrder.technicianName)
            }

            Divider()

            Text("Work Completed")
                .font(.subheadline)
                .fontWeight(.medium)
            Text(workOrder.workDescription)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .card()
    }
}

struct DetailRow: View {
    let label: String
    let value: String

    /// Scales with Dynamic Type instead of a fixed 85pt, so long labels stop
    /// truncating at larger text sizes.
    @ScaledMetric(relativeTo: .subheadline) private var labelWidth: CGFloat = 85

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Layout.gapTight) {
            Text(label)
                .font(.subheadline)
                .fontWeight(.medium)
                .frame(width: labelWidth, alignment: .leading)
            Text(value)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        // Read as "Customer, Jane Smith" rather than "Customer:" then the value.
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label), \(value)")
    }
}
