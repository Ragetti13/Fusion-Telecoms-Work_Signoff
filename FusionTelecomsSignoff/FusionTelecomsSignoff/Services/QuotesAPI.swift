import Foundation

// MARK: - Wire models
//
// These mirror the Quote Builder server's response schemas (lib/api-zod in
// the Quote-Builder-Pro repo is the source of truth). Decoding ignores any
// extra fields the server adds, so additive server changes never break the
// app; a renamed or removed field surfaces as a decode error.

struct QuoteListItem: Decodable, Identifiable {
    let id: Int
    let customerId: Int?
    let customerName: String
    let customerReference: String?
    let status: String                 // "draft" | "converted" | "declined" | "lost"
    let validDays: Int
    let marginPercent: Double?
    let contractType: String?          // "standard" | "monthly" | "job"
    let contractPeriodMonths: Int?
    let upfrontPaymentPercent: Double?
    let isRenewal: Bool?
    let version: Int
    let rootQuoteId: Int?
    let isLatestVersion: Bool?
    let optionalCount: Int?
    let acceptedOptionalCount: Int?
    let oneOffTotal: Double?
    let recurringTotal: Double?
    let termValue: Double?
    let acceptedAt: String?
    let createdAt: String

    var isDraft: Bool { status == "draft" }
    var isClosed: Bool { status == "declined" || status == "lost" }
    var isSuperseded: Bool { isLatestVersion == false }
}

struct QuoteLineItem: Decodable, Identifiable {
    let id: Int
    let productNameSnapshot: String
    let productDescriptionSnapshot: String?
    let productCategorySnapshot: String   // "one_off" | "monthly_recurring"
    let quantity: Double
    let unitSalePriceSnapshot: Double
    let lineTotal: Double
    let lineMarginPercent: Double?
    let isOptional: Bool?
    let optionalSelected: Bool?
    let discountType: String?          // "percent" | "amount"
    let discountValue: Double?
    // Lines sharing a bundleKey present to the customer as one named group
    // with a subtotal; internally every line keeps its price and margin.
    let bundleKey: String?
    let bundleTitle: String?
    let discountAmount: Double?
    let productCaveatSnapshot: String?

    var isMonthly: Bool { productCategorySnapshot == "monthly_recurring" }
    var isIncluded: Bool { (isOptional ?? false) == false || (optionalSelected ?? false) }
}

struct QuoteSummary: Decodable {
    let quoteId: Int
    let customerName: String
    let status: String
    let oneOffTotal: Double
    let recurringTotal: Double
    let totalMarginAmount: Double
    let totalMarginPercent: Double
    let upfrontPaymentPercent: Double?
    let upfrontPayment: Double?
    let lineItems: [QuoteLineItem]
}

// MARK: - Auth

/// Bearer-token sign-in for the quote-building endpoints (the sign-off job
/// endpoints keep using the X-Signoff-Key). Tokens last 12 hours server-side;
/// this caches one and signs in again when it is near expiry or rejected.
actor QuotesSession {
    static let shared = QuotesSession()

    private var token: String?
    private var tokenFetchedAt: Date?

    struct Credentials {
        var baseURL: String
        var username: String
        var password: String
    }

    enum AuthError: LocalizedError {
        case notConfigured
        case loginFailed(String)

        var errorDescription: String? {
            switch self {
            case .notConfigured:
                return "Add your Quote Builder username and password in Settings first."
            case .loginFailed(let message):
                return message
            }
        }
    }

    func invalidate() { token = nil; tokenFetchedAt = nil }

    /// A valid bearer token, signing in if there isn't a fresh one cached.
    func bearerToken(_ creds: Credentials) async throws -> String {
        if let token, let fetched = tokenFetchedAt,
           Date().timeIntervalSince(fetched) < 11 * 60 * 60 {
            return token
        }
        return try await login(creds)
    }

    private func login(_ creds: Credentials) async throws -> String {
        guard !creds.username.isEmpty, !creds.password.isEmpty else {
            throw AuthError.notConfigured
        }
        let base = creds.baseURL.trimmingCharacters(in: .init(charactersIn: "/"))
        guard let url = URL(string: "\(base)/api/auth/login") else { throw URLError(.badURL) }
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "username": creds.username,
            "password": creds.password,
        ])
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let msg = obj["error"] as? String {
                throw AuthError.loginFailed(msg)
            }
            throw AuthError.loginFailed("Quote Builder sign-in failed (HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)).")
        }
        struct LoginResponse: Decodable { let token: String }
        let fresh = try JSONDecoder().decode(LoginResponse.self, from: data).token
        token = fresh
        tokenFetchedAt = Date()
        return fresh
    }
}

// MARK: - API

/// Quote-building endpoints. All are JWT-authed; QuotesSession handles the
/// sign-in and one transparent retry when a cached token has been rejected.
enum QuotesAPI {
    static func listQuotes(creds: QuotesSession.Credentials) async throws -> [QuoteListItem] {
        try await get("/api/quotes", creds: creds)
    }

    static func quoteSummary(id: Int, creds: QuotesSession.Credentials) async throws -> QuoteSummary {
        try await get("/api/quotes/\(id)/summary", creds: creds)
    }

    /// Create a draft quote for a free-text customer name. Returns the new id.
    static func createQuote(customerName: String, reference: String?, creds: QuotesSession.Credentials) async throws -> Int {
        var body: [String: Any?] = ["customerName": customerName]
        if let reference, !reference.isEmpty { body["customerReference"] = reference }
        let data = try await send(path: "/api/quotes", method: "POST", body: body, creds: creds)
        struct Created: Decodable { let id: Int }
        return try JSONDecoder().decode(Created.self, from: data).id
    }

    static func addLineItem(quoteId: Int, productId: Int, quantity: Int, isOptional: Bool, creds: QuotesSession.Credentials) async throws {
        var body: [String: Any?] = ["productId": productId, "quantity": quantity]
        if isOptional { body["isOptional"] = true }
        _ = try await send(path: "/api/quotes/\(quoteId)/line-items", method: "POST", body: body, creds: creds)
    }

    /// Patch one or more line fields. Pass NSNull() to clear a nullable field
    /// (e.g. discountType/discountValue to remove a discount).
    static func updateLineItem(quoteId: Int, lineItemId: Int, fields: [String: Any?], creds: QuotesSession.Credentials) async throws {
        _ = try await send(path: "/api/quotes/\(quoteId)/line-items/\(lineItemId)", method: "PATCH", body: fields, creds: creds)
    }

    static func deleteLineItem(quoteId: Int, lineItemId: Int, creds: QuotesSession.Credentials) async throws {
        _ = try await send(path: "/api/quotes/\(quoteId)/line-items/\(lineItemId)", method: "DELETE", body: nil, creds: creds)
    }

    // MARK: bundles

    struct QuoteBundle: Decodable { let key: String; let title: String }

    /// Create a bundle from the given lines. Returns the bundle's key.
    static func createBundle(quoteId: Int, title: String, lineItemIds: [Int], creds: QuotesSession.Credentials) async throws -> String {
        let data = try await send(
            path: "/api/quotes/\(quoteId)/bundles", method: "POST",
            body: ["title": title, "lineItemIds": lineItemIds], creds: creds
        )
        return try JSONDecoder().decode(QuoteBundle.self, from: data).key
    }

    /// Rename a bundle and/or move lines in or out of it.
    static func updateBundle(
        quoteId: Int, key: String,
        title: String? = nil, addLineItemIds: [Int]? = nil, removeLineItemIds: [Int]? = nil,
        creds: QuotesSession.Credentials
    ) async throws {
        var body: [String: Any?] = [:]
        if let title { body["title"] = title }
        if let addLineItemIds { body["addLineItemIds"] = addLineItemIds }
        if let removeLineItemIds { body["removeLineItemIds"] = removeLineItemIds }
        _ = try await send(path: "/api/quotes/\(quoteId)/bundles/\(key)", method: "PATCH", body: body, creds: creds)
    }

    /// Dissolve a bundle; its lines stay on the quote with prices shown again.
    static func deleteBundle(quoteId: Int, key: String, creds: QuotesSession.Credentials) async throws {
        _ = try await send(path: "/api/quotes/\(quoteId)/bundles/\(key)", method: "DELETE", body: nil, creds: creds)
    }

    /// Re-fetch one quote (the single-quote response decodes into the same
    /// model; list-only extras like termValue just come back nil).
    static func getQuote(id: Int, creds: QuotesSession.Credentials) async throws -> QuoteListItem {
        try await get("/api/quotes/\(id)", creds: creds)
    }

    /// Patch quote fields (contractType, contractPeriodMonths,
    /// upfrontPaymentPercent, isRenewal, ...). NSNull() sends an explicit null.
    static func updateQuote(id: Int, fields: [String: Any?], creds: QuotesSession.Credentials) async throws {
        _ = try await send(path: "/api/quotes/\(id)", method: "PATCH", body: fields, creds: creds)
    }

    /// Customer-facing accept link for a draft quote (…/q/<token>).
    static func shareQuoteURL(id: Int, creds: QuotesSession.Credentials) async throws -> URL {
        let data = try await send(path: "/api/quotes/\(id)/share", method: "POST", body: nil, creds: creds)
        struct Shared: Decodable { let publicToken: String }
        let token = try JSONDecoder().decode(Shared.self, from: data).publicToken
        let base = creds.baseURL.trimmingCharacters(in: .init(charactersIn: "/"))
        guard let url = URL(string: "\(base)/q/\(token)") else { throw URLError(.badURL) }
        return url
    }

    /// Convert a draft to an order. Returns the new order's id.
    static func convertQuote(id: Int, contractType: String, periodMonths: Int?, creds: QuotesSession.Credentials) async throws -> Int {
        var body: [String: Any?] = ["contractType": contractType]
        if let periodMonths { body["contractPeriodMonths"] = periodMonths }
        let data = try await send(path: "/api/quotes/\(id)/convert", method: "POST", body: body, creds: creds)
        struct Converted: Decodable { let id: Int }
        return try JSONDecoder().decode(Converted.self, from: data).id
    }

    /// Close a draft off as "declined" (customer said no) or "lost" (went
    /// elsewhere). The quote becomes read-only and the linked CRM opportunity
    /// is marked lost; reopening undoes both.
    static func closeQuote(id: Int, outcome: String, creds: QuotesSession.Credentials) async throws {
        _ = try await send(path: "/api/quotes/\(id)/close", method: "POST", body: ["outcome": outcome], creds: creds)
    }

    /// Reopen a declined/lost quote as an editable draft.
    static func reopenQuote(id: Int, creds: QuotesSession.Credentials) async throws {
        _ = try await send(path: "/api/quotes/\(id)/reopen", method: "POST", body: nil, creds: creds)
    }

    /// Customer-facing signing link for an order (…/o/<token>).
    static func shareOrderURL(orderId: Int, creds: QuotesSession.Credentials) async throws -> URL {
        let data = try await send(path: "/api/orders/\(orderId)/share", method: "POST", body: nil, creds: creds)
        struct Shared: Decodable { let publicToken: String }
        let token = try JSONDecoder().decode(Shared.self, from: data).publicToken
        let base = creds.baseURL.trimmingCharacters(in: .init(charactersIn: "/"))
        guard let url = URL(string: "\(base)/o/\(token)") else { throw URLError(.badURL) }
        return url
    }

    // MARK: request plumbing

    private static func get<T: Decodable>(_ path: String, creds: QuotesSession.Credentials) async throws -> T {
        let data = try await send(path: path, method: "GET", body: nil, creds: creds)
        return try JSONDecoder().decode(T.self, from: data)
    }

    static func send(
        path: String,
        method: String,
        body: [String: Any?]?,
        creds: QuotesSession.Credentials
    ) async throws -> Data {
        let base = creds.baseURL.trimmingCharacters(in: .init(charactersIn: "/"))
        guard let url = URL(string: "\(base)\(path)") else { throw URLError(.badURL) }

        func attempt(_ token: String) async throws -> (Data, HTTPURLResponse) {
            var request = URLRequest(url: url, timeoutInterval: 20)
            request.httpMethod = method
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            if let body {
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = try JSONSerialization.data(
                    withJSONObject: body.compactMapValues { $0 is NSNull ? NSNull() : $0 })
            }
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
            return (data, http)
        }

        var token = try await QuotesSession.shared.bearerToken(creds)
        var (data, http) = try await attempt(token)
        if http.statusCode == 401 {
            // The cached token expired server-side — sign in again, once.
            await QuotesSession.shared.invalidate()
            token = try await QuotesSession.shared.bearerToken(creds)
            (data, http) = try await attempt(token)
        }
        guard (200...299).contains(http.statusCode) else {
            if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let msg = obj["error"] as? String {
                throw NSError(domain: "QuotesAPI", code: http.statusCode,
                              userInfo: [NSLocalizedDescriptionKey: msg])
            }
            throw NSError(domain: "QuotesAPI", code: http.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: "Server returned HTTP \(http.statusCode)."])
        }
        return data
    }
}

// MARK: - Formatting helpers shared by the quote views

enum QuoteFormat {
    static func currency(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "GBP"
        return formatter.string(from: NSNumber(value: value)) ?? "£\(value)"
    }

    static func shortDate(_ iso: String) -> String {
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = parser.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)
        guard let date else { return iso.prefix(10).description }
        return date.formatted(date: .abbreviated, time: .omitted)
    }
}
