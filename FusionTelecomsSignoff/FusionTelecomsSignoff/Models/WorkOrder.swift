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
    // Filenames of install photos stored on disk for this job (see PhotoStore).
    // Kept as filenames, not inline data, so UserDefaults stays small.
    var photoFilenames: [String]

    // Installation details captured at sign-off (all optional).
    var serialNumber: String?
    var macAddress: String?
    var routerDownMbps: Double?
    var routerUpMbps: Double?
    var wifiDownMbps: Double?
    var wifiUpMbps: Double?

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
        remoteJobId: Int? = nil,
        photoFilenames: [String] = [],
        serialNumber: String? = nil,
        macAddress: String? = nil,
        routerDownMbps: Double? = nil,
        routerUpMbps: Double? = nil,
        wifiDownMbps: Double? = nil,
        wifiUpMbps: Double? = nil
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
        self.photoFilenames = photoFilenames
        self.serialNumber = serialNumber
        self.macAddress = macAddress
        self.routerDownMbps = routerDownMbps
        self.routerUpMbps = routerUpMbps
        self.wifiDownMbps = wifiDownMbps
        self.wifiUpMbps = wifiUpMbps
    }

    /// True when any installation detail has been captured.
    var hasInstallDetails: Bool {
        (serialNumber?.isEmpty == false) || (macAddress?.isEmpty == false)
            || routerDownMbps != nil || routerUpMbps != nil
            || wifiDownMbps != nil || wifiUpMbps != nil
    }

    /// "12.3 / 4.5 Mbps" (down/up), or a single value, or nil if neither set.
    static func speedText(down: Double?, up: Double?) -> String? {
        switch (down, up) {
        case let (d?, u?): return "\(clean(d)) ↓ / \(clean(u)) ↑ Mbps"
        case let (d?, nil): return "\(clean(d)) ↓ Mbps"
        case let (nil, u?): return "\(clean(u)) ↑ Mbps"
        default: return nil
        }
    }

    private static func clean(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }

    var signatureImage: UIImage? {
        guard let data = signatureData else { return nil }
        return UIImage(data: data)
    }

    var displayName: String {
        jobReference.isEmpty ? "Job" : jobReference
    }

    /// Install photos for this job, loaded from disk in stored order.
    var photos: [UIImage] {
        photoFilenames.compactMap { PhotoStore.load($0, for: id) }
    }

    // Custom decode so jobs saved before customerEmail was added still load correctly
    enum CodingKeys: String, CodingKey {
        case id, jobReference, customerName, customerAddress, customerEmail
        case workDescription, completedDate, technicianName, signatureData, isSigned
        case remoteJobId, photoFilenames
        case serialNumber, macAddress, routerDownMbps, routerUpMbps, wifiDownMbps, wifiUpMbps
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
        photoFilenames = (try? c.decode([String].self, forKey: .photoFilenames)) ?? []
        serialNumber   = try? c.decode(String.self, forKey: .serialNumber)
        macAddress     = try? c.decode(String.self, forKey: .macAddress)
        routerDownMbps = try? c.decode(Double.self, forKey: .routerDownMbps)
        routerUpMbps   = try? c.decode(Double.self, forKey: .routerUpMbps)
        wifiDownMbps   = try? c.decode(Double.self, forKey: .wifiDownMbps)
        wifiUpMbps     = try? c.decode(Double.self, forKey: .wifiUpMbps)
    }
}

/// On-disk store for a job's install photos. Photos live under
/// Documents/JobPhotos/<jobID>/ as downscaled JPEGs, referenced by filename
/// from the WorkOrder so they don't bloat UserDefaults.
enum PhotoStore {
    private static func directory(for jobID: UUID) -> URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("JobPhotos", isDirectory: true)
            .appendingPathComponent(jobID.uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    /// Persist images (downscaled) and return the filenames stored, appended to
    /// any already present for the job.
    @discardableResult
    static func save(_ images: [UIImage], for jobID: UUID) -> [String] {
        var names: [String] = []
        for image in images {
            guard let data = downscaled(image).jpegData(compressionQuality: 0.7) else { continue }
            let name = UUID().uuidString + ".jpg"
            let url = directory(for: jobID).appendingPathComponent(name)
            if (try? data.write(to: url)) != nil { names.append(name) }
        }
        return names
    }

    static func load(_ name: String, for jobID: UUID) -> UIImage? {
        UIImage(contentsOfFile: directory(for: jobID).appendingPathComponent(name).path)
    }

    static func delete(_ name: String, for jobID: UUID) {
        try? FileManager.default.removeItem(at: directory(for: jobID).appendingPathComponent(name))
    }

    static func deleteAll(for jobID: UUID) {
        try? FileManager.default.removeItem(at: directory(for: jobID))
    }

    /// Cap the longest edge so stored photos stay a sensible size.
    private static func downscaled(_ image: UIImage, maxEdge: CGFloat = 1600) -> UIImage {
        let longest = max(image.size.width, image.size.height)
        guard longest > maxEdge else { return image }
        let scale = maxEdge / longest
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
