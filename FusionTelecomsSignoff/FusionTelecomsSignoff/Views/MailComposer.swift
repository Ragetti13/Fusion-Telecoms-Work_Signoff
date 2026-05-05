import SwiftUI
import MessageUI

struct MailComposer: UIViewControllerRepresentable {
    let toAddress: String
    let ccAddresses: [String]
    let subject: String
    let body: String
    let pdfURL: URL
    var onFinished: (MFMailComposeResult) -> Void

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let composer = MFMailComposeViewController()
        composer.mailComposeDelegate = context.coordinator
        if !toAddress.isEmpty {
            composer.setToRecipients([toAddress])
        }
        if !ccAddresses.isEmpty {
            composer.setCcRecipients(ccAddresses)
        }
        composer.setSubject(subject)
        composer.setMessageBody(body, isHTML: false)
        if let data = try? Data(contentsOf: pdfURL) {
            composer.addAttachmentData(data, mimeType: "application/pdf", fileName: pdfURL.lastPathComponent)
        }
        return composer
    }

    func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinished: onFinished) }

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        var onFinished: (MFMailComposeResult) -> Void
        init(onFinished: @escaping (MFMailComposeResult) -> Void) { self.onFinished = onFinished }

        func mailComposeController(_ controller: MFMailComposeViewController,
                                   didFinishWith result: MFMailComposeResult,
                                   error: Error?) {
            controller.dismiss(animated: true)
            onFinished(result)
        }
    }
}

// Builds the completion email body for a signed work order
func signOffEmailBody(for job: WorkOrder) -> String {
    let ref = job.jobReference.isEmpty ? "N/A" : job.jobReference
    let addr = job.customerAddress.isEmpty ? "N/A" : job.customerAddress
    let tech = job.technicianName.isEmpty ? "Fusion Telecoms" : job.technicianName

    return """
Dear \(job.customerName),

Please find attached your Work Completion Certificate for the job carried out at \(addr).

Job Reference:  \(ref)
Date Completed: \(job.completedDate.formatted(date: .long, time: .shortened))

Work Completed:
\(job.workDescription)

By signing the certificate you confirmed that the work was completed to your satisfaction. \
A copy of the signed certificate is attached to this email for your records.

If you have any questions please contact us at support@fusion-telecoms.com

Kind regards,
\(tech)
Fusion Telecoms
support@fusion-telecoms.com
"""
}
