import Foundation
import Kitura
import LoggerAPI

public struct LanguageQualityPair {
    let langcode : String
    let matchQuality : Float

    init (negotiatedLanguage: String, matchQuality: Float = 0) {
        self.langcode = negotiatedLanguage
        self.matchQuality = matchQuality
    }
}

public class AcceptLanguage : RouterMiddleware {

    public enum NegotiationStatus {
        case NegotiationIncomplete, NoAcceptLanguageHeader, NoMatch, Matched
    }

    public var negotiationStatus : NegotiationStatus = .NegotiationIncomplete
    public var negotiatedLanguage : LanguageQualityPair?

    let sendContentLanguageHeader: Bool
    let langsToAccept: [String]

    public init(acceptLangs: [String], sendContentLanguageHeader: Bool = true) {
        self.sendContentLanguageHeader = sendContentLanguageHeader
        self.langsToAccept = acceptLangs
    }

    public func handle(request: RouterRequest, response: RouterResponse, next: @escaping () -> Void) {
        defer {
            next()
        }

        guard langsToAccept.count > 0 else {
            Log.error("Language negotiation attempted with no accepted languages defined; match impossible")
            negotiationStatus = .NoMatch
            return
        }

        guard let acceptHeader = request.headers["Accept-Language"] else {
            negotiationStatus = .NoAcceptLanguageHeader
            negotiatedLanguage = LanguageQualityPair(negotiatedLanguage: langsToAccept.first!)
            return
        }

        // Mad props to http://nshipster.com/nsregularexpression/ for helping me
        // navigate the ridiculousness that is RegEx in Swift.
        let pattern = try! NSRegularExpression(pattern: "([a-zA-Z-]+|\\*)(?:.+?([\\d\\.]+))?")

        var currentBestMatch: LanguageQualityPair?

        for acceptable in acceptHeader.components(separatedBy: ",") {
            let acceptableCount = acceptable.utf16.count
            guard let match = pattern.firstMatch(in: acceptable, options: [], range: NSRange(location: 0, length: acceptableCount)) else {
                // This code seems to be seriously malformed.
                continue
            }

            // Extract the langcode
            let langcodeRange = match.rangeAt(1)
            let start = String.UTF16Index(langcodeRange.location)
            let end = String.UTF16Index(langcodeRange.location + langcodeRange.length)
            var langcode = String(acceptable.utf16[start..<end])!
            if langcode == "*" {
                langcode = langsToAccept.first!
            }

            let quality: Float?
            let qualityRange = match.rangeAt(2)
            if qualityRange.location == NSNotFound {
                // If there's no quality specified, use 1.
                quality = 1.0
            }
            else {
                // Extract the quality.
                let start = String.UTF16Index(qualityRange.location)
                let end = String.UTF16Index(qualityRange.location + qualityRange.length)
                quality = Float(String(acceptable.utf16[start..<end])!)
                // "all languages which are assigned a quality factor greater
                // than 0 are acceptable," so treat a best match with a quality
                // of 0 as no match at all. (If quality was so malformed that we
                // couldn't parse it, treat that as zero.)
                if quality == nil || quality == 0 {
                    continue;
                }
            }

            if langsToAccept.index(of: langcode) != nil && (currentBestMatch == nil || quality! > currentBestMatch!.matchQuality) {
                currentBestMatch = LanguageQualityPair(negotiatedLanguage: langcode, matchQuality: quality!)
                if quality! == 1.0 {
                    // We can't do better than this, so stop iterating.
                    break
                }
            }
        }

        // "all languages which are assigned a quality factor greater than 0 are
        // acceptable," so treat a best match with a quality of 0 as no match at
        // all.
        if currentBestMatch == nil {
            negotiationStatus = .NoMatch
            negotiatedLanguage = LanguageQualityPair(negotiatedLanguage: langsToAccept.first!, matchQuality: 0)
        }
        else {
            negotiationStatus = .Matched
            negotiatedLanguage = currentBestMatch
        }

        if sendContentLanguageHeader {
            response.headers.append("Content-Language", value: negotiatedLanguage!.langcode)
        }
    }
}
