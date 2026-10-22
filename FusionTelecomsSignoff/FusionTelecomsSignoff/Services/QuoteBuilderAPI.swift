import Foundation

struct LeadInput {
    var name: String
    var companyName: String = ""
    var email: String = ""
    var phone: String = ""
    var address: String = ""
    var notes: String = ""
}

/// Returned by POST /api/leads — the CRM ids plus the Quote Builder customer
/// the lead was mirrored into, so the app can open a pre-filled quote.
struct LeadResult: Decodable {
    let contactId: String
    let opportunityId: String
    let customerId: Int
}

/// GET /api/contact-lookup result: whether an existing CRM contact matches the
/// entered email/phone, and their current opportunities.
struct ContactLookupResult: Decodable {
    let found: Bool
    let contact: ContactSummary?
    let opportunities: [ContactOpportunity]
}

struct ContactSummary: Decodable {
    let id: String
    let name: String?
    let companyName: String?
    let email: String?
    let phone: String?
}

struct ContactOpportunity: Decodable, Identifiable {
    let id: String
    let name: String
    let pipelineName: String?
    let stageName: String?
    let status: String?
    let monetaryValue: Double?
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
    @discardableResult
    static func submitLead(_ lead: LeadInput, baseURL: String, apiKey: String) async throws -> LeadResult {
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
        return try JSONDecoder().decode(LeadResult.self, from: data)
    }

    /// Look up an existing CRM contact by email and/or phone before logging a
    /// lead, so the technician can avoid duplicates and see open opportunities.
    static func lookupContact(email: String, phone: String, baseURL: String, apiKey: String) async throws -> ContactLookupResult {
        var comps = URLComponents(string: "\(trim(baseURL))/api/contact-lookup")
        var qs: [URLQueryItem] = []
        if !email.isEmpty { qs.append(URLQueryItem(name: "email", value: email)) }
        if !phone.isEmpty { qs.append(URLQueryItem(name: "phone", value: phone)) }
        comps?.queryItems = qs
        guard let url = comps?.url else { throw URLError(.badURL) }
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue(apiKey, forHTTPHeaderField: "X-Signoff-Key")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw apiError(data: data, response: response)
        }
        return try JSONDecoder().decode(ContactLookupResult.self, from: data)
    }

    /// The Quote Builder web URL for a new quote pre-filled with this customer.
    static func newQuoteURL(baseURL: String, customerId: Int) -> URL? {
        URL(string: "\(trim(baseURL))/quotes/new?customerId=\(customerId)")
    }

    static func searchPriceBook(query: String, category: String?, baseURL: String, apiKey: String) async throws -> [PriceBookItem] {
        var comps = URLComponents(string: "\(trim(baseURL))/api/price-book")
        var qs: [URLQueryItem] = []
        if !query.isEmpty { qs.append(URLQueryItem(name: "q", value: query)) }
        if let category, !category.isEmpty { qs.append(URLQueryItem(name: "category", value: category)) }
        if !qs.isEmpty { comps?.queryItems = qs }
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
