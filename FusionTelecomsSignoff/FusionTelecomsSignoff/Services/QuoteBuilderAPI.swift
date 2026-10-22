import Foundation

struct LeadInput {
    var name: String
    var companyName: String = ""
    var email: String = ""
    var phone: String = ""
    var address: String = ""
    var notes: String = ""
}

struct PriceBookItem: Codable, Identifiable {
    let id: Int
    let sku: String?
    let name: String
    let description: String?
    let brand: String?
    let category: String            // "one_off" | "monthly_recurring"
    let salePrice: Double
    let caveat: String?
    let minimumTermMonths: Int?
    let isHardware: Bool

    var isMonthly: Bool { category == "monthly_recurring" }
}

/// Calls to the Quote Builder server for the field-app features (leads, pricing).
/// All authenticate with the X-Signoff-Key, like the sign-off job endpoints.
enum QuoteBuilderAPI {
    static func submitLead(_ lead: LeadInput, baseURL: String, apiKey: String) async throws {
        guard let url = URL(string: "\(trim(baseURL))/api/leads") else { throw URLError(.badURL) }
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "X-Signoff-Key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = ["name": lead.name]
        if !lead.companyName.isEmpty { body["companyName"] = lead.companyName }
        if !lead.email.isEmpty { body["email"] = lead.email }
        if !lead.phone.isEmpty { body["phone"] = lead.phone }
        if !lead.address.isEmpty { body["address"] = lead.address }
        if !lead.notes.isEmpty { body["notes"] = lead.notes }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw apiError(data: data, response: response)
        }
    }

    static func searchPriceBook(query: String, baseURL: String, apiKey: String) async throws -> [PriceBookItem] {
        var comps = URLComponents(string: "\(trim(baseURL))/api/price-book")
        if !query.isEmpty { comps?.queryItems = [URLQueryItem(name: "q", value: query)] }
        guard let url = comps?.url else { throw URLError(.badURL) }
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue(apiKey, forHTTPHeaderField: "X-Signoff-Key")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw apiError(data: data, response: response)
        }
        return try JSONDecoder().decode([PriceBookItem].self, from: data)
    }

    private static func trim(_ url: String) -> String {
        url.trimmingCharacters(in: .init(charactersIn: "/"))
    }

    /// Surface the server's { "error": ... } message when present.
    private static func apiError(data: Data, response: URLResponse) -> Error {
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let msg = obj["error"] as? String {
            return NSError(domain: "QuoteBuilderAPI", code: code,
                           userInfo: [NSLocalizedDescriptionKey: msg])
        }
        return NSError(domain: "QuoteBuilderAPI", code: code,
                       userInfo: [NSLocalizedDescriptionKey: "Server returned HTTP \(code)."])
    }
}
