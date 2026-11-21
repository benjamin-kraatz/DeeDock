import Foundation

/// The drop questions the person answered, each for exactly the question and the file it was about.
///
/// A drag asks before a flagged file leaves (``FlixDropConfirmation/sensitive(itemID:reason:destination:)``)
/// and before an older version leaves while a newer one exists
/// (``FlixDropConfirmation/newerVersion(itemID:newerID:)``). An answer lets the next drags go ahead
/// for ``lifetime``, but only past that one question:
/// - **Scoped by kind.** Answering the version question never answers the sensitive one, and the
///   reverse. A drag holding a flagged older version asks both, one after the other.
/// - **Scoped by item and file.** An approval names the item and the file identity its row listed
///   when the person answered (`FlixItem.fileIdentity`, compared in memory). A different item, or the
///   same row after its file was replaced, is asked again. A version answer also names the newer
///   item it was asked about, so a yet newer version asks again.
/// - **Use Newer grants nothing.** Swapping in the newer version answers the version question by
///   removing the older item from the drag; the newer item has not been asked about, so its own
///   sensitive verdict (and anything else) is evaluated afresh.
///
/// A value type owned by `FlixCoordinator`; it never touches the disk.
nonisolated struct FlixDropApprovals: Sendable {
    /// How long an answer lets the same drag through.
    static let lifetime: TimeInterval = 30

    nonisolated enum Kind: Hashable, Sendable {
        case sensitive
        /// An older version, sent although `newerID` exists.
        case olderVersion(newerID: FlixItem.ID)
    }

    private struct Key: Hashable, Sendable {
        var kind: Kind
        var itemID: FlixItem.ID
        var identity: FlixFileIdentity?
    }

    private var expiry: [Key: Date] = [:]

    init() {}

    /// The approval a question asks for: its kind and the item it names.
    static func subject(of confirmation: FlixDropConfirmation) -> (kind: Kind, itemID: FlixItem.ID) {
        switch confirmation {
        case .sensitive(let id, _, _): (.sensitive, id)
        case .newerVersion(let id, let newer): (.olderVersion(newerID: newer), id)
        }
    }

    /// Records that the person let `confirmation` go ahead for `item` (the item the question names,
    /// as the history lists it now).
    mutating func approve(_ confirmation: FlixDropConfirmation, item: FlixItem, now: Date = .now) {
        let subject = Self.subject(of: confirmation)
        guard subject.itemID == item.id else { return }
        prune(now: now)
        expiry[Key(kind: subject.kind, itemID: item.id, identity: item.fileIdentity)] = now.addingTimeInterval(Self.lifetime)
    }

    /// Whether `confirmation` was answered for `item` as it is listed now, within ``lifetime``.
    func covers(_ confirmation: FlixDropConfirmation, item: FlixItem, now: Date = .now) -> Bool {
        let subject = Self.subject(of: confirmation)
        guard subject.itemID == item.id,
              let until = expiry[Key(kind: subject.kind, itemID: item.id, identity: item.fileIdentity)] else { return false }
        return until > now
    }

    /// Whether a sensitive answer for `item` as it is listed now is still current.
    func coversSensitive(_ item: FlixItem, now: Date = .now) -> Bool {
        covers(.sensitive(itemID: item.id, reason: nil, destination: nil), item: item, now: now)
    }

    /// Forgets every answer.
    mutating func removeAll() { expiry = [:] }

    private mutating func prune(now: Date) {
        expiry = expiry.filter { $0.value > now }
    }
}
