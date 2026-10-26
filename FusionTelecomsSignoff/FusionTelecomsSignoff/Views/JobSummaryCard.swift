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
        VStack(alignment: .leading, spacing: 12) {
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
            }

            Divider()

            DetailRow(label: "Customer", value: workOrder.customerName)

            if !workOrder.customerAddress.isEmpty {
                DetailRow(label: "Address", value: workOrder.customerAddress)
                if let url = directionsURL {
                    Link(destination: url) {
                        Label("Directions", systemImage: "map.fill")
                            .font(.subheadline).fontWeight(.semibold)
                    }
                    .buttonStyle(.bordered)
                    .tint(.brandPink)
                    .padding(.leading, 85)
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
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.06), radius: 6, x: 0, y: 2)
    }
}

struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top) {
            Text(label + ":")
                .font(.subheadline)
                .fontWeight(.medium)
                .frame(width: 85, alignment: .leading)
            Text(value)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }
}
