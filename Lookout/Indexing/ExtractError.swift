// Adapted from DigUp (MIT, © 2026 Abdur Rahim) — https://github.com/ARahim3/DigUp

/// Why one file couldn't be read. The file is marked `skipped` (`tooSmall`) or `failed`; its neighbours go on.
nonisolated enum ExtractError: Error, CustomStringConvertible {
    case unreadable(String)
    case tooSmall(Int, Int)
    case locked
    case empty(String)

    var description: String {
        switch self {
        case .unreadable(let why): "unreadable: \(why)"
        case .tooSmall(let width, let height): "small image \(width)×\(height)"
        case .locked: "password-protected"
        case .empty(let why): why
        }
    }
}
