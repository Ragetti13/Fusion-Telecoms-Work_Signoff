import SwiftUI
import UIKit

struct NewJobView: View {
    @EnvironmentObject var store: WorkOrderStore
    @Environment(\.dismiss) var dismiss
    @StateObject private var locationManager: LocationManager

    @State private var jobReference: String
    @State private var customerName: String
    @State private var customerAddress: String
    @State private var customerEmail: String
    @State private var workDescription: String
    @State private var completedDate: Date
    @State private var showingPDFImport: Bool

    init(prefill: JobPrefill? = nil) {
        _locationManager = StateObject(wrappedValue: LocationManager())
        _jobReference    = State(initialValue: prefill?.jobReference    ?? "")
        _customerName    = State(initialValue: prefill?.customerName    ?? "")
        _customerAddress = State(initialValue: prefill?.customerAddress ?? "")
        _customerEmail   = State(initialValue: prefill?.customerEmail   ?? "")
        _workDescription = State(initialValue: prefill?.workDescription ?? "")
        _completedDate   = State(initialValue: Date())
        _showingPDFImport = State(initialValue: false)
    }

    private var isValid: Bool {
        !customerName.trimmingCharacters(in: .whitespaces).isEmpty &&
        !workDescription.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button {
                        showingPDFImport = true
                    } label: {
                        Label("Import from PDF Order Form", systemImage: "doc.text.magnifyingglass")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                Section("Job Details") {
                    TextField("Job Reference (e.g. JOB-001)", text: $jobReference)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.characters)
                    DatePicker("Date Completed", selection: $completedDate, displayedComponents: [.date, .hourAndMinute])
                }

                Section("Customer Details") {
                    TextField("Customer Name *", text: $customerName)

                    TextField("Customer Email", text: $customerEmail)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    TextField("Site Address", text: $customerAddress, axis: .vertical)
                        .lineLimit(2...4)

                    Button(action: fetchLocation) {
                        HStack(spacing: 6) {
                            if locationManager.isLocating {
                                ProgressView().scaleEffect(0.75)
                                Text("Locating…").font(.subheadline)
                            } else {
                                Image(systemName: "location.fill")
                                Text("Use Current Location").font(.subheadline)
                            }
                        }
                    }
                    .disabled(locationManager.isLocating)
                }

                Section {
                    TextField("Describe the work completed...", text: $workDescription, axis: .vertical)
                        .lineLimit(4...10)
                } header: {
                    Text("Work Completed *")
                }

                Section {
                    Button(action: saveJob) {
                        HStack {
                            Spacer()
                            Text("Save Job").fontWeight(.semibold)
                            Spacer()
                        }
                    }
                    .disabled(!isValid)
                }
            }
            .navigationTitle("New Job")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(isPresented: $showingPDFImport) {
                PDFImportView(
                    jobReference: $jobReference,
                    customerName: $customerName,
                    customerAddress: $customerAddress,
                    customerEmail: $customerEmail,
                    workDescription: $workDescription
                )
            }
            .alert("Location Error", isPresented: Binding(
                get: { locationManager.errorMessage != nil },
                set: { if !$0 { locationManager.errorMessage = nil } }
            )) {
                Button("OK") {}
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
            } message: {
                Text(locationManager.errorMessage ?? "")
            }
        }
    }

    private func fetchLocation() {
        locationManager.fetchAddress { address in
            customerAddress = address
        }
    }

    private func saveJob() {
        let job = WorkOrder(
            jobReference: jobReference.trimmingCharacters(in: .whitespaces),
            customerName: customerName.trimmingCharacters(in: .whitespaces),
            customerAddress: customerAddress.trimmingCharacters(in: .whitespaces),
            customerEmail: customerEmail.trimmingCharacters(in: .whitespaces),
            workDescription: workDescription.trimmingCharacters(in: .whitespaces),
            completedDate: completedDate,
            technicianName: store.technicianName
        )
        store.add(job)
        dismiss()
    }
}
