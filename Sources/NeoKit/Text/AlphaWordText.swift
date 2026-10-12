import Foundation

/// Decodes AlphaWord file bytes into a Unicode string.
/// Ported from neotools `text_file.export_text_from_neo`.
public enum AlphaWordText {
    public static func decode(_ data: some Collection<UInt8>, map: [UInt32] = CharacterMap.enUS) -> String {
        let bytes = Array(data)
        var scalars = String.UnicodeScalarView()
        var i = 0
        while i < bytes.count {
            var code = bytes[i]
            i += 1
            var escaped = false
            switch code {
            case 0xA4, 0xA7:
                continue  // unused / padding
            case 0x0D:
                code = 0x0A
            case 0x81, 0xA1:
                code = 0x20  // line-breaking space
            case 0x8D, 0xA3:
                code = 0x09  // line-breaking tab
            case 0x8F:
                continue  // hard break inside a long run of characters
            case 0xAD:
                code = 0x2D  // line-breaking hyphen
            case 0xB0:
                // Escape: 0xB0 <code> 0xB0
                guard i < bytes.count else { continue }
                escaped = true
                code = bytes[i]
                i += 1
                if i < bytes.count, bytes[i] == 0xB0 { i += 1 }
            case 0xA1...0xBF:
                continue  // untrapped escape
            default:
                break
            }
            if !escaped, code == 0x09 || code == 0x0A || code == 0x0D {
                scalars.append(Unicode.Scalar(code))
            } else if let scalar = Unicode.Scalar(map[Int(code)]) {
                scalars.append(scalar)
            }
        }
        return String(scalars)
    }
}
