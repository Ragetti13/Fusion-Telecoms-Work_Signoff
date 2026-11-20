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
    let status: String                 // "draft" | "converted"
    let validDays: Int
    let marginPercent: Double?
    let contractType: String?          // "standard" | "monthly" | "job"
    let contractPeriodMonths: Int?
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
