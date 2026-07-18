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
}
