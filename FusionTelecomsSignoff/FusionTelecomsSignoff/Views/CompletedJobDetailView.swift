import SwiftUI

struct CompletedJobDetailView: View {
    let workOrder: WorkOrder

    @State private var pdfURL: URL?
    @State private var showingShare = false

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    /// More photo columns where there's width for them (Duo inner display, iPad).
    private var photoColumns: Int { horizontalSizeClass == .regular ? 5 : 3 }

    var body: some View {
        ScrollView {
            VStack(spacing: Layout.gapSection) {
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
                .clipShape(RoundedRectangle(cornerRadius: Layout.radiusCard, style: .continuous))

                JobSummaryCard(workOrder: workOrder)

                if workOrder.hasInstallDetails {
                    VStack(alignment: .leading, spacing: Layout.gapTight) {
                        Text("Installation Details").font(.headline)
                        if let serial = workOrder.serialNumber, !serial.isEmpty {
                            DetailRow(label: "Serial", value: serial)
                        }
                        if let mac = workOrder.macAddress, !mac.isEmpty {
                            DetailRow(label: "MAC", value: mac)
                        }
                        if let r = WorkOrder.speedText(down: workOrder.routerDownMbps, up: workOrder.routerUpMbps) {
                            DetailRow(label: "Router", value: r)
                        }
                        if let w = WorkOrder.speedText(down: workOrder.wifiDownMbps, up: workOrder.wifiUpMbps) {
                            DetailRow(label: "Wi-Fi", value: w)
                        }
                    }
                    .card()
                }

                if let image = workOrder.signatureImage {
                    VStack(alignment: .leading, spacing: Layout.gapTight) {
                        Text("Customer Signature")
                            .font(.headline)

                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 140)
                            .accessibilityLabel("Customer signature")
                            .card()
                    }
                }

                let photos = workOrder.photos
                if !photos.isEmpty {
                    VStack(alignment: .leading, spacing: Layout.gapTight) {
                        Text("Install Photos")
                            .font(.headline)
                        LazyVGrid(
                            columns: Array(
                                repeating: GridItem(.flexible(), spacing: Layout.gapTight),
                                count: photoColumns
                            ),
                            spacing: Layout.gapTight
                        ) {
                            ForEach(Array(photos.enumerated()), id: \.offset) { index, image in
                                Image(uiImage: image)
                                    .resizable().scaledToFill()
                                    .frame(height: 100)
                                    .frame(maxWidth: .infinity)
                                    .clipped()
                                    .clipShape(RoundedRectangle(cornerRadius: Layout.radiusSmall))
                                    .accessibilityLabel("Install photo \(index + 1) of \(photos.count)")
                            }
                        }
                    }
                }

                Button(action: exportPDF) {
                    Label("Export as PDF", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .brandPrimaryButton()
            }
            .padding()
            .readableColumn()
        }
        .navigationTitle(workOrder.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .brandNavigationBar()
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

