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
    @State private var installType: InstallType = .inPerson

    // "Customer not available to sign" flow
    @State private var showingUnavailable = false
    @State private var unavailableGoLiveDate = Date()
    @State private var unavailableInstallType: InstallType = .remote
    @State private var deliverAfterUnavailable = false

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

                    Picker("Install Type", selection: $installType) {
                        ForEach(InstallType.allCases) { type in
                            Text(type.label).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)

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

                    Divider()

                    Button {
                        unavailableGoLiveDate = Date()
                        unavailableInstallType = .remote
                        showingUnavailable = true
                    } label: {
                        Label("Customer not available to sign", systemImage: "person.fill.questionmark")
                            .font(.subheadline)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.blue)
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
        // Customer-not-available: technician records the go-live date + install type
        .sheet(isPresented: $showingUnavailable, onDismiss: deliverCompletionIfNeeded) {
            NavigationStack {
                Form {
                    Section {
                        DatePicker("Go-Live Date", selection: $unavailableGoLiveDate, displayedComponents: .date)
                        Picker("Install Type", selection: $unavailableInstallType) {
                            ForEach(InstallType.allCases) { type in
                                Text(type.label).tag(type)
                            }
                        }
                    } header: {
                        Text("Record Completion")
                    } footer: {
                        Text("Use this when the customer isn't present to sign. The job is recorded as completed and the go-live date you enter is sent to the CRM.")
                    }
                    Section {
                        Button("Record Completion") { completeWithoutSignature() }
                            .fontWeight(.semibold)
                    }
                }
                .navigationTitle("No Signature")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Cancel") { showingUnavailable = false }
                    }
                }
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

        // Customer signed on-site today → report completion so the CRM
        // opportunity is marked live (go-live = today, install type as selected).
        let selectedInstallType = installType
        Task { [updated] in
            await store.reportCompletion(
                for: updated,
                goLiveDate: Date(),
                installType: selectedInstallType,
                signedByCustomer: true
            )
        }

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

    // Complete the job without a customer signature: the technician records the
    // go-live date and install type, the job is marked complete, and the CRM
    // opportunity is moved live against the supplied date (signedByCustomer=false).
    private func completeWithoutSignature() {
        var updated = workOrder
        updated.isSigned = true
        store.update(updated)
        signedOrder = updated

        let goLive = unavailableGoLiveDate
        let installType = unavailableInstallType
        Task { [updated] in
            await store.reportCompletion(
                for: updated,
                goLiveDate: goLive,
                installType: installType,
                signedByCustomer: false
            )
        }

        let pdfData = PDFGenerator.generate(from: updated)
        let filename = "WorkOrder-\(updated.displayName).pdf"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try? pdfData.write(to: url)
        pdfURL = url

        // Dismiss this sheet first; present mail/share from its onDismiss so
        // two sheets never fight to present at once.
        deliverAfterUnavailable = true
        showingUnavailable = false
    }

    private func deliverCompletionIfNeeded() {
        guard deliverAfterUnavailable else { return }
        deliverAfterUnavailable = false
        if MFMailComposeViewController.canSendMail() {
            showingMailComposer = true
        } else {
            showingShareSheet = true
        }
    }
}
