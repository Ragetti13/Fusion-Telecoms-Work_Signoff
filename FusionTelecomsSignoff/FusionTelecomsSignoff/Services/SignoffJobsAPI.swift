import Foundation

struct RemoteJob: Codable, Identifiable {
    let id: Int
    let orderId: Int
    let jobReference: String
    let customerName: String
    let customerAddress: String?
    let customerEmail: String?
    let workDescription: String?
    let status: String
}

enum SignoffError: LocalizedError {
    case crmNotConfigured
    var errorDescription: String? {
        switch self {
        case .crmNotConfigured:
            return "The CRM integration isn't set up on the server yet, so there are no Provisioning jobs to pull."
        }
    }
}

enum InstallType: String, CaseIterable, Identifiable {
    case inPerson = "In-person"
    case remote = "Remote"
    var id: String { rawValue }
    var label: String { rawValue }
}

/// Installation details sent with a completion report (all optional).
struct SignoffInstall {
    var serialNumber: String? = nil
    var macAddress: String? = nil
    var routerDownMbps: Double? = nil
    var routerUpMbps: Double? = nil
    var wifiDownMbps: Double? = nil
    var wifiUpMbps: Double? = nil
}

enum SignoffJobsAPI {
    static func fetchPending(baseURL: String, apiKey: String) async throws -> [RemoteJob] {
        guard let url = URL(string: "\(baseURL.trimmingCharacters(in: .init(charactersIn: "/")))/api/signoff-jobs/pending") else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue(apiKey, forHTTPHeaderField: "X-Signoff-Key")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode([RemoteJob].self, from: data)
    }

    /// Fetch jobs currently in the CRM's Provisioning stage (the server matches
    /// each to its Quote Builder order and ensures a sign-off job exists).
    static func fetchProvisioning(baseURL: String, apiKey: String) async throws -> [RemoteJob] {
        guard let url = URL(string: "\(baseURL.trimmingCharacters(in: .init(charactersIn: "/")))/api/signoff-jobs/provisioning") else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.setValue(apiKey, forHTTPHeaderField: "X-Signoff-Key")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard http.statusCode == 200 else {
            // 503 = CRM not configured on the server; surface a clear message.
            if http.statusCode == 503 { throw SignoffError.crmNotConfigured }
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode([RemoteJob].self, from: data)
    }

    static func claimJob(id: Int, baseURL: String, apiKey: String) async throws {
        guard let url = URL(string: "\(baseURL.trimmingCharacters(in: .init(charactersIn: "/")))/api/signoff-jobs/\(id)/claim") else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.httpMethod = "PATCH"
        request.setValue(apiKey, forHTTPHeaderField: "X-Signoff-Key")
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }

    /// Report a job signed off. The server records completion and moves the
    /// linked CRM opportunity to its live stage. goLiveDate is YYYY-MM-DD.
    static func completeJob(
        id: Int,
        goLiveDate: String,
        installType: InstallType,
        signedByCustomer: Bool,
        install: SignoffInstall = SignoffInstall(),
        baseURL: String,
        apiKey: String
    ) async throws {
        guard let url = URL(string: "\(baseURL.trimmingCharacters(in: .init(charactersIn: "/")))/api/signoff-jobs/\(id)/complete") else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.httpMethod = "PATCH"
        request.setValue(apiKey, forHTTPHeaderField: "X-Signoff-Key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = [
            "goLiveDate": goLiveDate,
            "installType": installType.rawValue,
            "signedByCustomer": signedByCustomer,
        ]
        if let s = install.serialNumber, !s.isEmpty { body["serialNumber"] = s }
        if let m = install.macAddress, !m.isEmpty { body["macAddress"] = m }
        if let v = install.routerDownMbps { body["routerDownMbps"] = v }
        if let v = install.routerUpMbps { body["routerUpMbps"] = v }
        if let v = install.wifiDownMbps { body["wifiDownMbps"] = v }
        if let v = install.wifiUpMbps { body["wifiUpMbps"] = v }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }

    /// Formats a date as the YYYY-MM-DD the completion endpoint expects.
    static func isoDay(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
}
