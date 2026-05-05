import Foundation

struct ExtractedPDFFields {
    var jobReference: String = ""
    var customerName: String = ""
    var address: String = ""
    var customerEmail: String = ""
    var workDescription: String = ""
}

struct PDFFieldExtractor {

    static func extract(from text: String) -> ExtractedPDFFields {
        var fields = ExtractedPDFFields()
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        for (i, line) in lines.enumerated() {
            let lower = line.lowercased()
            let next = i + 1 < lines.count ? lines[i + 1] : ""

            if fields.jobReference.isEmpty {
                let patterns = ["job ref", "job reference", "reference no", "ref no", "order no",
                                "order number", "job no", "job number", "work order", "wo#", "wo no"]
                if let v = match(line: line, lower: lower, next: next, patterns: patterns) {
                    fields.jobReference = v
                }
            }

            if fields.customerName.isEmpty {
                let patterns = ["customer name", "customer:", "client name", "client:",
                                "contact name", "contact:", "name:"]
                if let v = match(line: line, lower: lower, next: next, patterns: patterns) {
                    fields.customerName = v
                }
            }

            if fields.address.isEmpty {
                let patterns = ["site address", "site:", "address:", "location:", "property:",
                                "premises:", "install address", "service address"]
                if lower.containsAny(patterns) {
                    var parts: [String] = []
                    if let inline = extractInline(from: line, lower: lower, patterns: patterns) {
                        parts.append(inline)
                    }
                    var j = i + 1
                    while j < lines.count && j <= i + 4 {
                        let nl = lines[j].lowercased()
                        if nl.contains(":") && !looksLikeAddressLine(lines[j]) { break }
                        parts.append(lines[j])
                        j += 1
                    }
                    if !parts.isEmpty { fields.address = parts.joined(separator: ", ") }
                }
            }

            if fields.customerEmail.isEmpty {
                let patterns = ["customer email", "client email", "email address",
                                "e-mail address", "e-mail:", "email:"]
                if let v = match(line: line, lower: lower, next: next, patterns: patterns) {
                    // Validate it looks like an email before accepting
                    if v.contains("@") { fields.customerEmail = v }
                }
            }

            if fields.workDescription.isEmpty {
                let patterns = ["work description", "description of work", "scope of work",
                                "work carried out", "works:", "description:", "work completed",
                                "details:", "fault details", "job details", "works completed"]
                if lower.containsAny(patterns) {
                    var parts: [String] = []
                    if let inline = extractInline(from: line, lower: lower, patterns: patterns) {
                        parts.append(inline)
                    }
                    var j = i + 1
                    while j < lines.count && j <= i + 10 {
                        let nl = lines[j].lowercased()
                        if nl.contains(":") && nl.count < 40 { break }
                        parts.append(lines[j])
                        j += 1
                    }
                    if !parts.isEmpty {
                        fields.workDescription = parts
                            .joined(separator: "\n")
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                }
            }
        }

        // Regex fallback: find any email address in the full text if not already found
        if fields.customerEmail.isEmpty {
            fields.customerEmail = firstEmail(in: text) ?? ""
        }

        return fields
    }

    // MARK: - Helpers

    private static func match(line: String, lower: String, next: String, patterns: [String]) -> String? {
        guard lower.containsAny(patterns) else { return nil }
        if let v = extractInline(from: line, lower: lower, patterns: patterns) { return v }
        return next.isEmpty ? nil : next
    }

    private static func extractInline(from line: String, lower: String, patterns: [String]) -> String? {
        for pattern in patterns {
            guard let range = lower.range(of: pattern) else { continue }
            var after = String(line[range.upperBound...]).trimmingCharacters(in: .whitespaces)
            if after.first == ":" || after.first == "-" || after.first == "–" {
                after = String(after.dropFirst()).trimmingCharacters(in: .whitespaces)
            }
            return after.isEmpty ? nil : after
        }
        return nil
    }

    private static func looksLikeAddressLine(_ line: String) -> Bool {
        let lower = line.lowercased()
        let hasDigit = line.contains { $0.isNumber }
        let addressWords = ["road", "street", "avenue", "lane", "drive", "close", "way",
                            "court", "place", "estate", "industrial", "business"]
        return hasDigit || addressWords.contains { lower.contains($0) }
    }

    private static func firstEmail(in text: String) -> String? {
        let pattern = "[A-Za-z0-9._%+\\-]+@[A-Za-z0-9.\\-]+\\.[A-Za-z]{2,}"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range, in: text)
        else { return nil }
        return String(text[range])
    }
}

private extension String {
    func containsAny(_ patterns: [String]) -> Bool {
        let lower = self.lowercased()
        return patterns.contains { lower.contains($0) }
    }
}
