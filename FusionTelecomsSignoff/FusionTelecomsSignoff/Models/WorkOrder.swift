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
    // signoff_jobs.id for a job pulled from Quote Builder; lets the app report
    // completion back so the linked CRM opportunity can be marked live. nil for
    // jobs created locally (manually or via deep link).
    var remoteJobId: Int?

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
        isSigned: Bool = false,
        remoteJobId: Int? = nil
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
        self.remoteJobId = remoteJobId
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
        case remoteJobId
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
        remoteJobId    = try? c.decode(Int.self,    forKey: .remoteJobId)
    }
}
