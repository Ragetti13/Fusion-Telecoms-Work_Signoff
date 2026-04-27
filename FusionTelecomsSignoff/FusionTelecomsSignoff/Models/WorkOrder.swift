import Foundation
import UIKit

struct WorkOrder: Identifiable, Codable {
    let id: UUID
    var jobReference: String
    var customerName: String
    var customerAddress: String
    var workDescription: String
    var completedDate: Date
    var technicianName: String
    var signatureData: Data?
    var isSigned: Bool

    init(
        id: UUID = UUID(),
        jobReference: String = "",
        customerName: String = "",
        customerAddress: String = "",
        workDescription: String = "",
        completedDate: Date = Date(),
        technicianName: String = "",
        signatureData: Data? = nil,
        isSigned: Bool = false
    ) {
        self.id = id
        self.jobReference = jobReference
        self.customerName = customerName
        self.customerAddress = customerAddress
        self.workDescription = workDescription
        self.completedDate = completedDate
        self.technicianName = technicianName
        self.signatureData = signatureData
        self.isSigned = isSigned
    }

    var signatureImage: UIImage? {
        guard let data = signatureData else { return nil }
        return UIImage(data: data)
    }

    var displayName: String {
        jobReference.isEmpty ? "Job" : jobReference
    }
}
