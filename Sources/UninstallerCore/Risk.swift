import Foundation

/// How risky it is to remove an item. Drives the badge color, the default
/// selection state, and the pre-removal confirmation.
///
/// - `easy`: regenerable data (caches, build products). May be preselected.
/// - `review`: probably safe, but worth a human look first (name-only matches,
///   attachment copies, simulator contents).
/// - `tough`: hard or impossible to get back (device backups, large personal
///   files). Tough items are never preselected; that invariant is enforced in
///   `RemovableItem.init`, not left to callers.
public enum RiskLevel: String, Sendable, Equatable, Hashable, CaseIterable, Comparable {
    case easy
    case review
    case tough

    private var rank: Int {
        switch self {
        case .easy: return 0
        case .review: return 1
        case .tough: return 2
        }
    }

    public static func < (lhs: RiskLevel, rhs: RiskLevel) -> Bool {
        lhs.rank < rhs.rank
    }

    /// The level implied by a match confidence when a scanner says nothing more:
    /// precise bundle-id matches are easy, fuzzy name matches deserve review.
    public init(confidence: MatchConfidence) {
        self = (confidence == .bundleID) ? .easy : .review
    }

    /// Fallback reason shown when a scanner assigns no specific one.
    public var defaultReason: String {
        switch self {
        case .easy:
            return "Safe to remove; apps recreate what they need."
        case .review:
            return "Matched by name only, or the data may still be wanted; check before removing."
        case .tough:
            return "Hard to get back once the Trash is emptied."
        }
    }
}

/// Reclaimable space split by risk level, for the summary header shown above
/// each tab's item list.
public struct RiskSummary: Sendable, Equatable {
    public let easyBytes: Int64
    public let reviewBytes: Int64
    public let toughBytes: Int64

    public init(items: [RemovableItem]) {
        var easy: Int64 = 0
        var review: Int64 = 0
        var tough: Int64 = 0
        for item in items {
            let bytes = item.sizeBytes ?? 0
            switch item.risk {
            case .easy: easy += bytes
            case .review: review += bytes
            case .tough: tough += bytes
            }
        }
        easyBytes = easy
        reviewBytes = review
        toughBytes = tough
    }

    public var totalBytes: Int64 { easyBytes + reviewBytes + toughBytes }
}
