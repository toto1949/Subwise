import Foundation
import ImageIO
@preconcurrency import Vision

struct TrialCandidate: Sendable, Equatable {
    var merchant: String
    var trialEndDate: Date?
    var renewalPrice: Money?
    var frequency: String?
    var confidence: Double
    var normalizedText: String
}

protocol OCRService: Sendable { func recognizeTrial(in imageData: Data) async throws -> TrialCandidate }

struct VisionOCRService: OCRService {
    func recognizeTrial(in imageData: Data) async throws -> TrialCandidate {
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil), let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw CocoaError(.fileReadCorruptFile) }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let orientationValue = (properties?[kCGImagePropertyOrientation] as? NSNumber)?.uint32Value ?? 1
        let orientation = CGImagePropertyOrientation(rawValue: orientationValue) ?? .up
        let text = try await recognize(image, orientation: orientation)
        return TrialTextParser().parse(text)
    }

    private func recognize(_ image: CGImage, orientation: CGImagePropertyOrientation) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error { continuation.resume(throwing: error); return }
                let text = (request.results as? [VNRecognizedTextObservation])?.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n") ?? ""
                continuation.resume(returning: text)
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.automaticallyDetectsLanguage = true
            request.customWords = TrialTextParser.knownMerchantNames
            DispatchQueue.global(qos: .userInitiated).async {
                do { try VNImageRequestHandler(cgImage: image, orientation: orientation).perform([request]) } catch { continuation.resume(throwing: error) }
            }
        }
    }
}

struct TrialTextParser: Sendable {
    static let knownMerchantNames = [
        "Adobe Creative Cloud", "YouTube Premium", "Apple Music", "Amazon Prime", "Microsoft 365",
        "Google One", "PlayStation Plus", "Xbox Game Pass", "Dropbox", "Notion", "ChatGPT",
        "Netflix", "Spotify", "Canva", "iCloud+", "Disney+", "Hulu", "Max", "Paramount+",
        "Peacock", "Audible", "Headspace", "Duolingo", "Grammarly", "Adobe"
    ]

    func parse(_ raw: String) -> TrialCandidate {
        let text = raw.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
        let price = renewalPrice(in: text)
        let frequency = firstMatch(#"(?i)(weekly|week|monthly|month|yearly|annually|annual|year)"#, in: text)?.lowercased()
        let date = parseDate(in: text)
        let merchant = merchantName(in: raw)
        let present = [price != nil, frequency != nil, date != nil, !merchant.isEmpty].filter { $0 }.count
        return TrialCandidate(merchant: merchant, trialEndDate: date, renewalPrice: price, frequency: frequency, confidence: Double(present) / 4, normalizedText: text)
    }

    func decimalPrice(from input: String) -> Decimal? {
        var value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        value = value.replacingOccurrences(of: #"(?i)(USD|EUR|GBP|CAD|AUD|US\$)"#, with: "", options: .regularExpression)
        value = value.replacingOccurrences(of: #"[^0-9,.-]"#, with: "", options: .regularExpression)
        guard !value.isEmpty else { return nil }

        if value.contains(","), value.contains(".") {
            if let comma = value.lastIndex(of: ","), let dot = value.lastIndex(of: "."), comma > dot {
                value = value.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")
            } else {
                value = value.replacingOccurrences(of: ",", with: "")
            }
        } else if value.contains(",") {
            let digitsAfterComma = value.split(separator: ",", omittingEmptySubsequences: false).last?.count ?? 0
            value = digitsAfterComma == 3 ? value.replacingOccurrences(of: ",", with: "") : value.replacingOccurrences(of: ",", with: ".")
        }
        return Decimal(string: value, locale: Locale(identifier: "en_US_POSIX"))
    }

    private func firstMatch(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern), let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)), match.numberOfRanges > 1, let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }

    private func renewalPrice(in text: String) -> Money? {
        let pattern = #"(?i)(?:US\$|USD|EUR|GBP|CAD|AUD|[$€£])\s*([0-9]{1,3}(?:[,.\s][0-9]{3})+(?:[,.][0-9]{1,2})?|[0-9]+(?:[,.][0-9]{1,2})?)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))

        let candidates: [(money: Money, score: Int, position: Int)] = matches.compactMap { match in
            guard match.numberOfRanges > 1,
                  let amountRange = Range(match.range(at: 1), in: text),
                  let decimal = decimalPrice(from: String(text[amountRange])) else { return nil }
            let cents = NSDecimalNumber(decimal: decimal * 100).intValue
            guard cents > 0 else { return nil }

            let lowerBound = max(0, match.range.location - 45)
            let upperBound = min((text as NSString).length, NSMaxRange(match.range) + 45)
            let context = (text as NSString).substring(with: NSRange(location: lowerBound, length: upperBound - lowerBound)).lowercased()
            var score = 1
            if context.range(of: #"renew|then|after|charge|bill|price|per\s+(?:month|year|week)|/\s*(?:mo|month|yr|year|week)"#, options: .regularExpression) != nil { score += 5 }
            if context.range(of: #"save|discount|coupon|credit"#, options: .regularExpression) != nil { score -= 2 }
            return (Money(cents: cents), score, match.range.location)
        }
        return candidates.max { lhs, rhs in lhs.score == rhs.score ? lhs.position < rhs.position : lhs.score < rhs.score }?.money
    }

    private func merchantName(in raw: String) -> String {
        for merchant in Self.knownMerchantNames {
            if raw.range(of: merchant, options: [.caseInsensitive, .diacriticInsensitive]) != nil { return merchant }
        }

        let ignoredTerms = [
            "free trial", "trial ends", "subscription", "subscriptions", "manage plan", "payment", "billing",
            "confirmation", "receipt", "settings", "cancel", "continue", "restore", "purchase", "renews",
            "expires", "per month", "per year", "terms", "privacy", "welcome", "account"
        ]
        let lines = raw.components(separatedBy: .newlines)
            .map { $0.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return lines.enumerated().compactMap { index, line -> (String, Int)? in
            let lower = line.lowercased()
            guard line.rangeOfCharacter(from: .letters) != nil,
                  line.count >= 2, line.count <= 42,
                  line.split(separator: " ").count <= 6,
                  !ignoredTerms.contains(where: lower.contains),
                  lower.range(of: #"(?:[$€£]|\b(?:usd|eur|gbp)\b)|\d{1,2}:\d{2}|\d{1,2}[/-]\d{1,2}"#, options: .regularExpression) == nil else { return nil }
            var score = max(0, 8 - index)
            if line.first?.isUppercase == true { score += 2 }
            if line.split(separator: " ").count <= 3 { score += 2 }
            return (line, score)
        }.max { $0.1 < $1.1 }?.0 ?? ""
    }

    private func parseDate(in text: String) -> Date? {
        let patternsAndFormats: [(String, [String])] = [
            (#"(?i)((?:Jan(?:uary)?|Feb(?:ruary)?|Mar(?:ch)?|Apr(?:il)?|May|Jun(?:e)?|Jul(?:y)?|Aug(?:ust)?|Sep(?:tember)?|Oct(?:ober)?|Nov(?:ember)?|Dec(?:ember)?)\s+\d{1,2}(?:,?\s*\d{4})?)"#, ["MMMM d, yyyy", "MMM d, yyyy", "MMMM d yyyy", "MMM d yyyy", "MMMM d", "MMM d"]),
            (#"\b(\d{1,2}[/-]\d{1,2}(?:[/-]\d{2,4})?)\b"#, ["M/d/yyyy", "M-d-yyyy", "M/d/yy", "M-d-yy", "M/d", "M-d"]),
            (#"\b(\d{4}-\d{1,2}-\d{1,2})\b"#, ["yyyy-M-d"])
        ]
        for (pattern, formats) in patternsAndFormats {
            guard let match = firstMatch(pattern, in: text) else { continue }
            for format in formats {
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.dateFormat = format
                guard var date = formatter.date(from: match) else { continue }
                if !format.contains("y") {
                    let calendar = Calendar.current
                    let components = calendar.dateComponents([.month, .day], from: date)
                    date = calendar.date(from: DateComponents(year: calendar.component(.year, from: .now), month: components.month, day: components.day)) ?? date
                    if date < calendar.startOfDay(for: .now), let nextYear = calendar.date(byAdding: .year, value: 1, to: date) { date = nextYear }
                }
                return date
            }
        }
        return nil
    }
}
