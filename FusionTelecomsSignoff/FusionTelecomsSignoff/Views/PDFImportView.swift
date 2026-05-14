import SwiftUI
import PDFKit
import UniformTypeIdentifiers

struct PDFImportView: View {
    @Binding var jobReference: String
    @Binding var customerName: String
    @Binding var customerAddress: String
    @Binding var customerEmail: String
    @Binding var workDescription: String

    @Environment(\.dismiss) var dismiss
    @State private var showingFilePicker = false
    @State private var extractedFields: ExtractedPDFFields?
    @State private var isProcessing = false
    @State private var readError: String?

    var body: some View {
        NavigationStack {
            if let fields = extractedFields {
                FieldReviewView(fields: fields) { confirmed, updated in
                    if confirmed { apply(updated) }
                    dismiss()
                }
            } else {
                pickView
            }
        }
    }

    // MARK: - Pick screen

    private var pickView: some View {
        VStack(spacing: 28) {
            Spacer()
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 64))
                .foregroundStyle(.blue)
            VStack(spacing: 8) {
                Text("Import from PDF")
                    .font(.title2).fontWeight(.semibold)
                Text("Select a customer order form PDF and the app will read the job reference, customer name, address, email and work description.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 24)
            }
            if isProcessing {
                ProgressView("Reading PDF…").padding()
            } else {
                Button { showingFilePicker = true } label: {
                    Label("Choose PDF", systemImage: "folder.badge.plus")
                        .frame(width: 260)
                }
                .buttonStyle(.borderedProminent)
            }
            if let err = readError {
                Text(err)
                    .font(.caption).foregroundStyle(.red)
                    .multilineTextAlignment(.center).padding(.horizontal)
            }
            Spacer()
        }
        .navigationTitle("Import PDF")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
        }
        .fileImporter(isPresented: $showingFilePicker, allowedContentTypes: [.pdf]) { result in
            switch result {
            case .success(let url): processPDF(url: url)
            case .failure(let error): readError = error.localizedDescription
            }
        }
    }

    // MARK: - Processing

    private func processPDF(url: URL) {
        isProcessing = true
        readError = nil
        Task.detached(priority: .userInitiated) {
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            var fullText = ""
            if let pdf = PDFDocument(url: url) {
                for i in 0..<pdf.pageCount {
                    fullText += (pdf.page(at: i)?.string ?? "") + "\n"
                }
            }
            let fields = PDFFieldExtractor.extract(from: fullText)
            await MainActor.run {
                if fullText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    readError = "No readable text found. The PDF may be a scanned image."
                } else {
                    extractedFields = fields
                }
                isProcessing = false
            }
        }
    }

    private func apply(_ fields: ExtractedPDFFields) {
        if !fields.jobReference.isEmpty    { jobReference    = fields.jobReference }
        if !fields.customerName.isEmpty    { customerName    = fields.customerName }
        if !fields.address.isEmpty         { customerAddress = fields.address }
        if !fields.customerEmail.isEmpty   { customerEmail   = fields.customerEmail }
        if !fields.workDescription.isEmpty { workDescription = fields.workDescription }
    }
}

// MARK: - Field Review

struct FieldReviewView: View {
    @State var fields: ExtractedPDFFields
    let onComplete: (Bool, ExtractedPDFFields) -> Void

    var body: some View {
        Form {
            Section {
                Label("Review and edit the extracted fields before applying them to the job form.", systemImage: "info.circle")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Section("Job Reference") {
                TextField("Not detected", text: $fields.jobReference).autocorrectionDisabled()
            }
            Section("Customer Name") {
                TextField("Not detected", text: $fields.customerName)
            }
            Section("Site Address") {
                TextField("Not detected", text: $fields.address, axis: .vertical).lineLimit(2...4)
            }
            Section("Customer Email") {
                TextField("Not detected", text: $fields.customerEmail)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            Section("Work Description") {
                TextField("Not detected", text: $fields.workDescription, axis: .vertical).lineLimit(3...8)
            }
            Section {
                Button("Apply to Job Form") { onComplete(true, fields) }.fontWeight(.semibold)
                Button("Cancel", role: .cancel) { onComplete(false, fields) }.foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Extracted Data")
        .navigationBarTitleDisplayMode(.inline)
    }
}
