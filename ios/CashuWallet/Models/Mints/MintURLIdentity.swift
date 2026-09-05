import Foundation

enum MintURLIdentity {
    /// Normalize only URL components that are case-insensitive. Preserve the
    /// scheme and path boundary so distinct mint endpoints cannot alias.
    static func normalized(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmed),
              components.scheme != nil, components.host != nil else { return trimmed }
        components.scheme = components.scheme?.lowercased()
        components.host = components.host?.lowercased()
        if (components.scheme == "https" && components.port == 443)
            || (components.scheme == "http" && components.port == 80) {
            components.port = nil
        }
        var path = components.percentEncodedPath
        while path.hasSuffix("/") { path.removeLast() }
        components.percentEncodedPath = path
        return components.string ?? trimmed
    }
}
