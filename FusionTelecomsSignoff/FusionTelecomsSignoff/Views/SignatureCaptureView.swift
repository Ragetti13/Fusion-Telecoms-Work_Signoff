import SwiftUI
import UIKit

struct SignatureCaptureView: View {
    let workOrder: WorkOrder

    @EnvironmentObject var store: WorkOrderStore
    @Environment(\.dismiss) var dismiss

    @State private var signatureImage: UIImage?
    @State private var hasSignature = false
    @State private var padID = UUID()
    @State private var showingConfirm = false

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
            Button("Confirm") { saveSignature() }
        } message: {
            Text("Confirm \(workOrder.customerName) is signing off this job?")
        }
    }

    private func saveSignature() {
        guard let image = signatureImage else { return }
        var updated = workOrder
        updated.signatureData = image.pngData()
        updated.isSigned = true
        store.update(updated)
        dismiss()
    }
}
