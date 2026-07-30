import Foundation

/// Converts publisher-supplied HTML summaries into plain reading text.
///
/// Feeds routinely put escaped markup, inline images, "Read more" anchors, and
/// non-breaking spaces inside `<description>`. None of that belongs on the native
/// reading surface, so it is normalized once at parse time.
public enum HTMLTextNormalizer {
    private static let blockLevelTags: Set<String> = [
        "p", "div", "br", "li", "tr", "h1", "h2", "h3", "h4", "h5", "h6",
        "blockquote", "section", "article", "figure", "figcaption"
    ]

    private static let namedEntities: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'",
        "nbsp": "\u{00A0}", "hellip": "…", "mdash": "—", "ndash": "–",
        "lsquo": "\u{2018}", "rsquo": "\u{2019}", "ldquo": "\u{201C}",
        "rdquo": "\u{201D}", "middot": "·", "bull": "•", "copy": "©",
        "reg": "®", "trade": "™", "deg": "°", "eacute": "é", "egrave": "è",
        "uuml": "ü", "ouml": "ö", "auml": "ä", "ccedil": "ç", "ntilde": "ñ"
    ]

    /// Strips markup, decodes entities, and collapses whitespace.
    ///
    /// Tags are removed before entities are decoded so prose like `a &lt; b`
    /// survives. Feeds that escape their markup (`&lt;p&gt;`) reveal tags only
    /// after decoding, so a second strip runs when the decoded text still looks
    /// like markup.
    public static func plainText(from html: String) -> String {
        collapseWhitespace(in: decodedAndStripped(html))
    }

    private static func decodedAndStripped(_ html: String) -> String {
        let decoded = decodeEntities(in: stripTags(from: html))
        return containsMarkup(decoded) ? stripTags(from: decoded) : decoded
    }

    /// True when the text contains something shaped like `<tag>` — a `<` followed
    /// immediately by a letter or `/`. A lone comparison operator does not match.
    static func containsMarkup(_ text: String) -> Bool {
        var previousWasOpeningAngle = false
        for character in text {
            if previousWasOpeningAngle, character.isLetter || character == "/" {
                return true
            }
            previousWasOpeningAngle = character == "<"
        }
        return false
    }

    static func stripTags(from html: String) -> String {
        var output = ""
        var insideTag = false
        var tagName = ""
        var readingTagName = false

        for character in html {
            switch character {
            case "<":
                insideTag = true
                readingTagName = true
                tagName = ""
            case ">":
                guard insideTag else {
                    output.append(character)
                    continue
                }
                insideTag = false
                readingTagName = false
                let normalized = tagName
                    .trimmingCharacters(in: CharacterSet(charactersIn: "/ \n\t"))
                    .lowercased()
                if blockLevelTags.contains(normalized) {
                    output.append("\n")
                }
            default:
                if insideTag {
                    if readingTagName {
                        if character.isWhitespace {
                            readingTagName = false
                        } else {
                            tagName.append(character)
                        }
                    }
                } else {
                    output.append(character)
                }
            }
        }

        return output
    }

    static func decodeEntities(in text: String) -> String {
        guard text.contains("&") else { return text }

        var output = ""
        var index = text.startIndex

        while index < text.endIndex {
            let character = text[index]
            guard character == "&" else {
                output.append(character)
                index = text.index(after: index)
                continue
            }

            // An entity reference is short; anything longer is a literal ampersand.
            let searchLimit = text.index(index, offsetBy: 12, limitedBy: text.endIndex) ?? text.endIndex
            guard let semicolon = text[index..<searchLimit].firstIndex(of: ";") else {
                output.append(character)
                index = text.index(after: index)
                continue
            }

            let body = String(text[text.index(after: index)..<semicolon])
            if let replacement = decodeEntityBody(body) {
                output.append(replacement)
                index = text.index(after: semicolon)
            } else {
                output.append(character)
                index = text.index(after: index)
            }
        }

        return output
    }

    private static func decodeEntityBody(_ body: String) -> String? {
        if body.isEmpty { return nil }

        if body.hasPrefix("#") {
            let digits = String(body.dropFirst())
            let scalarValue: UInt32?
            if digits.lowercased().hasPrefix("x") {
                scalarValue = UInt32(digits.dropFirst(), radix: 16)
            } else {
                scalarValue = UInt32(digits, radix: 10)
            }
            guard let value = scalarValue, let scalar = Unicode.Scalar(value) else { return nil }
            return String(Character(scalar))
        }

        return namedEntities[body.lowercased()]
    }

    static func collapseWhitespace(in text: String) -> String {
        var output = ""
        var pendingSpace = false
        var pendingNewline = false

        for character in text {
            if character == "\n" || character == "\r" {
                pendingNewline = true
                continue
            }
            if character.isWhitespace {
                pendingSpace = true
                continue
            }
            if !output.isEmpty {
                if pendingNewline {
                    output.append(" ")
                } else if pendingSpace {
                    output.append(" ")
                }
            }
            pendingSpace = false
            pendingNewline = false
            output.append(character)
        }

        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Splits normalized text into paragraphs for feed-only rendering.
    public static func paragraphs(from html: String) -> [String] {
        decodedAndStripped(html)
            .components(separatedBy: .newlines)
            .map { collapseWhitespace(in: $0) }
            .filter { !$0.isEmpty }
    }
}
