import Foundation
import UIKit

struct WorkOrder: Identifiable, Codable {
    let id: UUID
    var jobReference: String
    var customerName: String
    var customerAddress: String
    var customerEmail: String
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
        customerEmail: String = "",
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
        self.customerEmail = customerEmail
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

    // Custom decode so jobs saved before customerEmail was added still load correctly
    enum CodingKeys: String, CodingKey {
        case id, jobReference, customerName, customerAddress, customerEmail
        case workDescription, completedDate, technicianName, signatureData, isSigned
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id             = try  c.decode(UUID.self,   forKey: .id)
        jobReference   = try  c.decode(String.self, forKey: .jobReference)
        customerName   = try  c.decode(String.self, forKey: .customerName)
        customerAddress = try c.decode(String.self, forKey: .customerAddress)
        customerEmail  = (try? c.decode(String.self, forKey: .customerEmail)) ?? ""
        workDescription = try c.decode(String.self, forKey: .workDescription)
        completedDate  = try  c.decode(Date.self,   forKey: .completedDate)
        technicianName = try  c.decode(String.self, forKey: .technicianName)
        signatureData  = try? c.decode(Data.self,   forKey: .signatureData)
        isSigned       = try  c.decode(Bool.self,   forKey: .isSigned)
    }
}
