import Foundation

struct JobPrefill {
    var jobReference: String
    var customerName: String
    var customerAddress: String
    var customerEmail: String
    var workDescription: String
}

enum DeepLinkHandler {
    static func parse(url: URL) -> JobPrefill? {
        guard url.scheme?.lowercased() == "ftsignoff",
              url.host?.lowercased() == "newjob" else { return nil }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let params = Dictionary(
            (components.queryItems ?? []).compactMap { item -> (String, String)? in
                guard let value = item.value else { return nil }
                return (item.name, value)
            },
            uniquingKeysWith: { first, _ in first }
        )
        return JobPrefill(
            jobReference: params["ref"] ?? "",
            customerName: params["customer"] ?? "",
            customerAddress: params["address"] ?? "",
            customerEmail: params["email"] ?? "",
            workDescription: params["work"] ?? ""
        )
    }
}
