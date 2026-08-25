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
        let text = try await recognize(image)
        return TrialTextParser().parse(text)
    }

    private func recognize(_ image: CGImage) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error { continuation.resume(throwing: error); return }
                let text = (request.results as? [VNRecognizedTextObservation])?.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n") ?? ""
                continuation.resume(returning: text)
            }
            request.recognitionLevel = .accurate; request.usesLanguageCorrection = true
            DispatchQueue.global(qos: .userInitiated).async {
                do { try VNImageRequestHandler(cgImage: image).perform([request]) } catch { continuation.resume(throwing: error) }
            }
        }
    }
}

struct TrialTextParser: Sendable {
    func parse(_ raw: String) -> TrialCandidate {
        let text = raw.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
        let price = firstMatch(#"\$\s?(\d+(?:\.\d{2})?)"#, in: text).flatMap { Decimal(string: $0) }.map { Money(cents: NSDecimalNumber(decimal: $0 * 100).intValue) }
        let frequency = firstMatch(#"(?i)(weekly|week|monthly|month|yearly|annual|year)"#, in: text)?.lowercased()
        let date = parseDate(in: text)
        let merchant = raw.split(separator: "\n").first.map(String.init)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let present = [price != nil, frequency != nil, date != nil, !merchant.isEmpty].filter { $0 }.count
        return TrialCandidate(merchant: merchant, trialEndDate: date, renewalPrice: price, frequency: frequency, confidence: Double(present) / 4, normalizedText: text)
    }

    private func firstMatch(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern), let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)), match.numberOfRanges > 1, let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }

    private func parseDate(in text: String) -> Date? {
        guard let match = firstMatch(#"(?i)((?:Jan(?:uary)?|Feb(?:ruary)?|Mar(?:ch)?|Apr(?:il)?|May|Jun(?:e)?|Jul(?:y)?|Aug(?:ust)?|Sep(?:tember)?|Oct(?:ober)?|Nov(?:ember)?|Dec(?:ember)?)\s+\d{1,2}(?:,\s*\d{4})?)"#, in: text) else { return nil }
        for format in ["MMMM d, yyyy", "MMM d, yyyy", "MMMM d", "MMM d"] { let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = format; if let date = formatter.date(from: match) { return date } }
        return nil
    }
}
