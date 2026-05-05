import SwiftUI
import UIKit
import MessageUI

private let supportEmail = "support@fusion-telecoms.com"

struct SignatureCaptureView: View {
    let workOrder: WorkOrder

    @EnvironmentObject var store: WorkOrderStore
    @Environment(\.dismiss) var dismiss

    @State private var signatureImage: UIImage?
    @State private var hasSignature = false
    @State private var padID = UUID()
    @State private var showingConfirm = false

    // Post sign-off email / share state
    @State private var signedOrder: WorkOrder?
    @State private var pdfURL: URL?
    @State private var showingMailComposer = false
    @State private var showingShareSheet = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                JobSummaryCard(workOrder: workOrder)

                VStack(alignment: .leading, spacing: 12) {
                    Text("Customer Signature")
                        .font(.headline)
                    Text("By signing below, I confirm that the above work has been completed to my satisfaction.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    SignaturePad(signatureImage: $signatureImage, hasSignature: $hasSignature)
                        .id(padID)
                        .frame(height: 180)

                    HStack {
                        Button("Clear") {
                            padID = UUID()
                            signatureImage = nil
                            hasSignature = false
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)

                        Spacer()

                        Button("Confirm Sign-Off") {
                            showingConfirm = true
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!hasSignature)
                    }
                }
                .padding()
                .background(Color(.systemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding()
        }
        .navigationTitle("Get Signature")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Confirm Sign-Off", isPresented: $showingConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Confirm") { saveAndEmail() }
        } message: {
            Text("Confirm \(workOrder.customerName) is signing off this job?")
        }
        // Mail composer — shown when device Mail is configured
        .sheet(isPresented: $showingMailComposer, onDismiss: { dismiss() }) {
            if let job = signedOrder, let url = pdfURL {
                MailComposer(
                    toAddress: job.customerEmail,
                    ccAddresses: [supportEmail],
                    subject: "Work Completion Certificate – \(job.displayName)",
                    body: signOffEmailBody(for: job),
                    pdfURL: url
                ) { _ in showingMailComposer = false }
            }
        }
        // Share sheet fallback — used when Mail is not configured on device
        .sheet(isPresented: $showingShareSheet, onDismiss: { dismiss() }) {
            if let url = pdfURL {
                ShareSheet(items: [url])
            }
        }
    }

    // MARK: - Actions

    private func saveAndEmail() {
        guard let image = signatureImage else { return }

        var updated = workOrder
        updated.signatureData = image.pngData()
        updated.isSigned = true
        store.update(updated)
        signedOrder = updated

        // Write PDF to a temp file so it can be attached or shared
        let pdfData = PDFGenerator.generate(from: updated)
        let filename = "WorkOrder-\(updated.displayName).pdf"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try? pdfData.write(to: url)
        pdfURL = url

        if MFMailComposeViewController.canSendMail() {
            showingMailComposer = true
        } else {
            // Device has no mail accounts configured — share sheet lets them
            // use AirDrop, WhatsApp, save to Files, etc.
            showingShareSheet = true
        }
    }
}
