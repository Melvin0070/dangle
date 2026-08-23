import Foundation

/// What the user picked from the Charm menu, overriding whatever charm the
/// pack itself names.
///
/// Persisted as a single string because that is what `UserDefaults` stores
/// well, but the encoding lives here rather than being re-parsed with
/// `hasPrefix` at each call site. The wire format is unchanged from when it
/// was parsed inline, so an override chosen by an older build still resolves.
public enum CharmOverride: RawRepresentable, Equatable, Hashable, Sendable {
    /// A charm installed in the `CharmStore`, by id.
    case installed(id: String)
    /// A bare emoji the user typed, hung as-is.
    case emoji(String)

    private static let emojiPrefix = "emoji:"

    public init?(rawValue: String) {
        if rawValue.isEmpty { return nil }
        if let glyph = rawValue.dropPrefix(Self.emojiPrefix) {
            guard !glyph.isEmpty else { return nil }
            self = .emoji(glyph)
        } else {
            self = .installed(id: rawValue)
        }
    }

    public var rawValue: String {
        switch self {
        case .installed(let id): id
        case .emoji(let glyph): Self.emojiPrefix + glyph
        }
    }

    /// The installed charm's id, or nil for an emoji — for ticking the right
    /// row in the Charm menu.
    public var installedID: String? {
        if case .installed(let id) = self { return id }
        return nil
    }

    public var isEmoji: Bool {
        if case .emoji = self { return true }
        return false
    }
}

private extension String {
    /// The remainder after `prefix`, or nil if it isn't there.
    func dropPrefix(_ prefix: String) -> String? {
        hasPrefix(prefix) ? String(dropFirst(prefix.count)) : nil
    }
}
