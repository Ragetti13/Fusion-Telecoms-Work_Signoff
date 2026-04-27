import SwiftUI

struct NewJobView: View {
    @EnvironmentObject var store: WorkOrderStore
    @Environment(\.dismiss) var dismiss

    @State private var jobReference = ""
    @State private var customerName = ""
    @State private var customerAddress = ""
    @State private var workDescription = ""
    @State private var completedDate = Date()

    private var isValid: Bool {
        !customerName.trimmingCharacters(in: .whitespaces).isEmpty &&
        !workDescription.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Job Details") {
                    TextField("Job Reference (e.g. JOB-001)", text: $jobReference)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.characters)
                    DatePicker("Date Completed", selection: $completedDate, displayedComponents: [.date, .hourAndMinute])
                }

                Section("Customer Details") {
                    TextField("Customer Name *", text: $customerName)
                    TextField("Site Address", text: $customerAddress, axis: .vertical)
                        .lineLimit(2...4)
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
                            Text("Save Job")
                                .fontWeight(.semibold)
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
        }
    }

    private func saveJob() {
        let job = WorkOrder(
            jobReference: jobReference.trimmingCharacters(in: .whitespaces),
            customerName: customerName.trimmingCharacters(in: .whitespaces),
            customerAddress: customerAddress.trimmingCharacters(in: .whitespaces),
            workDescription: workDescription.trimmingCharacters(in: .whitespaces),
            completedDate: completedDate,
            technicianName: store.technicianName
        )
        store.add(job)
        dismiss()
    }
}
