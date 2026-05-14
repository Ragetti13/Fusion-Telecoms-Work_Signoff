import SwiftUI

struct CompletedJobDetailView: View {
    let workOrder: WorkOrder

    @State private var pdfURL: URL?
    @State private var showingShare = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                HStack {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                    Text("Signed Off")
                        .fontWeight(.semibold)
                        .foregroundStyle(.green)
                    Spacer()
                    Text(workOrder.completedDate, style: .date)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .background(Color.green.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 12))

                JobSummaryCard(workOrder: workOrder)

                if let image = workOrder.signatureImage {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Customer Signature")
                            .font(.headline)

                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 140)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color(.systemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .shadow(color: .black.opacity(0.06), radius: 6, x: 0, y: 2)
                    }
                }

                Button(action: exportPDF) {
                    Label("Export as PDF", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .navigationTitle(workOrder.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingShare) {
            if let url = pdfURL {
                ShareSheet(items: [url])
            }
        }
    }

    private func exportPDF() {
        let data = PDFGenerator.generate(from: workOrder)
        let name = "WorkOrder-\(workOrder.displayName).pdf"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try? data.write(to: url)
        pdfURL = url
        showingShare = true
    }
}

