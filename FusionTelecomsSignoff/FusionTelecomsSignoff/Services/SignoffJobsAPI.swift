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

enum InstallType: String, CaseIterable, Identifiable {
    case inPerson = "In-person"
    case remote = "Remote"
    var id: String { rawValue }
    var label: String { rawValue }
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
        let body: [String: Any] = [
            "goLiveDate": goLiveDate,
            "installType": installType.rawValue,
            "signedByCustomer": signedByCustomer,
        ]
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
