import Foundation

/// Names saved drafts `YYYY-MM-DD HHMM <first line>.txt`.
public enum InboxNaming {
    static let maxTitleLength = 50

    public static func baseName(for text: String, date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd HHmm"
        return "\(formatter.string(from: date)) \(title(for: text))"
    }

    /// The first non-blank line, made safe for a file name and shortened to about 50 characters.
    public static func title(for text: String) -> String {
        let firstLine = text.split(whereSeparator: \.isNewline)
            .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? ""

        var cleaned = String(firstLine.unicodeScalars.map { scalar -> Character in
            if scalar == "/" || scalar == ":" { return " " }
            if CharacterSet.controlCharacters.contains(scalar) { return " " }
            return Character(scalar)
        })
        cleaned = cleaned.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        while cleaned.hasPrefix(".") { cleaned.removeFirst() }  // no hidden files

        if cleaned.count > maxTitleLength {
            let cut = String(cleaned.prefix(maxTitleLength))
            if let space = cut.lastIndex(of: " "), cut.distance(from: cut.startIndex, to: space) >= 20 {
                cleaned = String(cut[..<space])
            } else {
                cleaned = cut
            }
        }
        let trailing = CharacterSet.whitespaces.union(CharacterSet(charactersIn: ".,;-–—"))
        while let last = cleaned.unicodeScalars.last, trailing.contains(last) {
            cleaned.unicodeScalars.removeLast()
        }
        return cleaned.isEmpty ? "Untitled" : cleaned
    }

    /// `base.txt`, or `base 2.txt`, `base 3.txt`… if taken.
    static func candidates(base: String) -> some Sequence<String> {
        (1...).lazy.map { $0 == 1 ? "\(base).txt" : "\(base) \($0).txt" }
    }
}
