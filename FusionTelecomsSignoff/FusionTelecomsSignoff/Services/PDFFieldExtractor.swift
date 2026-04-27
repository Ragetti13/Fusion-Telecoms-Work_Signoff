import Foundation

struct ExtractedPDFFields {
    var jobReference: String = ""
    var customerName: String = ""
    var address: String = ""
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
                if let value = match(line: line, lower: lower, next: next, patterns: patterns) {
                    fields.jobReference = value
                }
            }

            if fields.customerName.isEmpty {
                let patterns = ["customer name", "customer:", "client name", "client:",
                                "contact name", "contact:", "name:"]
                if let value = match(line: line, lower: lower, next: next, patterns: patterns) {
                    fields.customerName = value
                }
            }

            if fields.address.isEmpty {
                let patterns = ["site address", "site:", "address:", "location:", "property:",
                                "premises:", "install address", "service address"]
                if lower.contains(where: patterns) {
                    // Collect up to 4 continuation lines for multi-line addresses
                    var parts: [String] = []
                    if let inline = extractInline(from: line, lower: lower, patterns: patterns) {
                        parts.append(inline)
                    }
                    var j = i + 1
                    while j < lines.count && j <= i + 4 {
                        let nextLower = lines[j].lowercased()
                        if nextLower.contains(":") && !looksLikeAddressLine(lines[j]) { break }
                        parts.append(lines[j])
                        j += 1
                    }
                    if !parts.isEmpty {
                        fields.address = parts.joined(separator: ", ")
                    }
                }
            }

            if fields.workDescription.isEmpty {
                let patterns = ["work description", "description of work", "scope of work",
                                "work carried out", "works:", "description:", "work completed",
                                "details:", "fault details", "job details", "works completed"]
                if lower.contains(where: patterns) {
                    var parts: [String] = []
                    if let inline = extractInline(from: line, lower: lower, patterns: patterns) {
                        parts.append(inline)
                    }
                    var j = i + 1
                    while j < lines.count && j <= i + 10 {
                        let nextLower = lines[j].lowercased()
                        // Stop if we hit another labelled field
                        if nextLower.contains(":") && nextLower.count < 40 { break }
                        parts.append(lines[j])
                        j += 1
                    }
                    if !parts.isEmpty {
                        fields.workDescription = parts.joined(separator: "\n")
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                }
            }
        }

        return fields
    }

    // MARK: - Helpers

    private static func match(line: String, lower: String, next: String, patterns: [String]) -> String? {
        guard lower.contains(where: patterns) else { return nil }
        if let inline = extractInline(from: line, lower: lower, patterns: patterns) {
            return inline
        }
        return next.isEmpty ? nil : next
    }

    private static func extractInline(from line: String, lower: String, patterns: [String]) -> String? {
        for pattern in patterns {
            guard let range = lower.range(of: pattern) else { continue }
            var after = String(line[range.upperBound...]).trimmingCharacters(in: .whitespaces)
            if after.hasPrefix(":") || after.hasPrefix("-") || after.hasPrefix("–") {
                after = String(after.dropFirst()).trimmingCharacters(in: .whitespaces)
            }
            return after.isEmpty ? nil : after
        }
        return nil
    }

    private static func looksLikeAddressLine(_ line: String) -> Bool {
        // Heuristic: short lines with digits or common address words are likely address continuations
        let lower = line.lowercased()
        let hasDigit = line.contains { $0.isNumber }
        let addressWords = ["road", "street", "avenue", "lane", "drive", "close", "way",
                            "court", "place", "estate", "industrial", "business"]
        return hasDigit || addressWords.contains { lower.contains($0) }
    }
}

private extension String {
    func contains(where patterns: [String]) -> Bool {
        let lower = self.lowercased()
        return patterns.contains { lower.contains($0) }
    }
}
