import SwiftUI
import UIKit
import PhotosUI
import VisionKit
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

    // Install photos captured on-site
    @State private var photos: [UIImage] = []
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var showingCamera = false

    // Installation details
    @State private var serialNumber = ""
    @State private var macAddress = ""
    @State private var routerDown = ""
    @State private var routerUp = ""
    @State private var wifiDown = ""
    @State private var wifiUp = ""
    @State private var scanTarget: ScanTarget?

    enum ScanTarget: Identifiable {
        case serial, mac
        var id: Int { self == .serial ? 0 : 1 }
    }

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

                installDetailsCard

                photosCard

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
                        .brandPrimaryButton()
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
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.brandPink)
                }
                .padding()
                .background(Color(.systemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding()
        }
        .navigationTitle("Get Signature")
        .navigationBarTitleDisplayMode(.inline)
        .brandNavigationBar()
        .fullScreenCover(isPresented: $showingCamera) {
            CameraPicker { image in photos.append(image) }
                .ignoresSafeArea()
        }
        .sheet(item: $scanTarget) { target in
            BarcodeScanner { code in
                switch target {
                case .serial: serialNumber = code
                case .mac: macAddress = code
                }
            }
            .ignoresSafeArea()
        }
        .onChange(of: pickerItems) { items in
            guard !items.isEmpty else { return }
            Task {
                for item in items {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        photos.append(image)
                    }
                }
                pickerItems = []
            }
        }
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
                        Button { completeWithoutSignature() } label: {
                            Text("Record Completion").frame(maxWidth: .infinity)
                        }
                        .brandPrimaryButton()
                    }
                }
                .navigationTitle("No Signature")
                .navigationBarTitleDisplayMode(.inline)
                .brandNavigationBar()
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Cancel") { showingUnavailable = false }
                    }
                }
            }
        }
    }

    // MARK: - Installation details

    private var installDetailsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Installation Details").font(.headline)
            Text("Added to the completion certificate.")
                .font(.subheadline).foregroundStyle(.secondary)

            labeledField("Router Serial", text: $serialNumber, scan: .serial)
            labeledField("MAC Address", text: $macAddress, scan: .mac)

            Text("Router speed (Mbps)").font(.subheadline).fontWeight(.medium)
            HStack(spacing: 10) {
                speedField("Download", text: $routerDown)
                speedField("Upload", text: $routerUp)
            }
            Text("Wi-Fi speed (Mbps)").font(.subheadline).fontWeight(.medium)
            HStack(spacing: 10) {
                speedField("Download", text: $wifiDown)
                speedField("Upload", text: $wifiUp)
            }
        }
        .padding()
        .background(Color(.systemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func labeledField(_ title: String, text: Binding<String>, scan: ScanTarget) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            HStack {
                TextField(title, text: text)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.characters)
                if BarcodeScanner.isAvailable {
                    Button { scanTarget = scan } label: {
                        Image(systemName: "barcode.viewfinder")
                    }
                    .buttonStyle(.bordered)
                    .tint(.brandPink)
                }
            }
        }
    }

    private func speedField(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .keyboardType(.decimalPad)
            .textFieldStyle(.roundedBorder)
    }

    private func applyInstallDetails(to order: inout WorkOrder) {
        func text(_ s: String) -> String? {
            let t = s.trimmingCharacters(in: .whitespaces)
            return t.isEmpty ? nil : t
        }
        func number(_ s: String) -> Double? {
            Double(s.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "."))
        }
        order.serialNumber = text(serialNumber)
        order.macAddress = text(macAddress)
        order.routerDownMbps = number(routerDown)
        order.routerUpMbps = number(routerUp)
        order.wifiDownMbps = number(wifiDown)
        order.wifiUpMbps = number(wifiUp)
    }

    // MARK: - Photos

    private var photosCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Install Photos").font(.headline)
                Spacer()
                if !photos.isEmpty {
                    Text("\(photos.count)").foregroundStyle(.secondary)
                }
            }
            Text("Attach before/after photos — they're added to the completion certificate.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if !photos.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(Array(photos.enumerated()), id: \.offset) { index, image in
                            ZStack(alignment: .topTrailing) {
                                Image(uiImage: image)
                                    .resizable().scaledToFill()
                                    .frame(width: 88, height: 88)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                Button {
                                    photos.remove(at: index)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .symbolRenderingMode(.palette)
                                        .foregroundStyle(.white, .black.opacity(0.55))
                                        .font(.system(size: 20))
                                }
                                .padding(3)
                            }
                        }
                    }
                }
            }

            HStack(spacing: 12) {
                Button { showingCamera = true } label: {
                    Label("Take Photo", systemImage: "camera.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.brandPink)

                PhotosPicker(selection: $pickerItems, maxSelectionCount: 10, matching: .images) {
                    Label("From Library", systemImage: "photo.on.rectangle").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.brandPink)
            }
        }
        .padding()
        .background(Color(.systemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Actions

    private func saveAndEmail() {
        guard let image = signatureImage else { return }

        var updated = workOrder
        updated.signatureData = image.pngData()
        updated.isSigned = true
        updated.photoFilenames = PhotoStore.save(photos, for: updated.id)
        applyInstallDetails(to: &updated)
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
        updated.photoFilenames = PhotoStore.save(photos, for: updated.id)
        applyInstallDetails(to: &updated)
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

/// Camera capture via UIImagePickerController (PhotosPicker can't take photos).
struct CameraPicker: UIViewControllerRepresentable {
    let onCapture: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { parent.onCapture(image) }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

/// Live barcode scanner (VisionKit) for capturing serials / MAC labels.
/// Tap a detected code to use it. Falls back to manual entry where the device
/// doesn't support scanning (the Scan button is hidden via `isAvailable`).
struct BarcodeScanner: UIViewControllerRepresentable {
    let onScan: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    static var isAvailable: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode()],
            qualityLevel: .balanced,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ controller: DataScannerViewController, context: Context) {
        try? controller.startScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let parent: BarcodeScanner
        init(_ parent: BarcodeScanner) { self.parent = parent }

        func dataScanner(_ dataScanner: DataScannerViewController, didTapOn item: RecognizedItem) {
            if case let .barcode(barcode) = item, let text = barcode.payloadStringValue {
                parent.onScan(text)
                parent.dismiss()
            }
        }
    }
}
