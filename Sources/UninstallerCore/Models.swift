import Foundation

/// How confident we are that a file belongs to a given app.
///
/// `.bundleID` matches are precise (reverse-DNS identity) and are pre-selected for
/// removal. `.name` matches are fuzzy suggestions (a folder merely named after the
/// app) and are surfaced *unchecked* so the user opts in deliberately.
public enum MatchConfidence: Sendable, Equatable {
    case bundleID
    case name
}

/// A single file or directory that can be moved to the Trash.
public struct RemovableItem: Identifiable, Sendable, Equatable {
    public let id: URL
    public var url: URL { id }
    /// Human label shown in the UI (e.g. "Application Support/Spotify").
    public let label: String
    /// The `~/Library` area this lives in (e.g. "Caches"), or "Application" for the
    /// `.app` bundle itself.
    public let category: String
    public let confidence: MatchConfidence
    /// How risky removing this item is: badge color, default selection, and the
    /// pre-removal alert all key off this.
    public let risk: RiskLevel
    /// One-line human explanation of the risk (e.g. "Regenerable by Xcode").
    public let riskReason: String
    /// On-disk allocated size in bytes. `nil` until computed.
    public var sizeBytes: Int64?
    /// Last content modification, when the scanner knows it (big-file rows).
    public let modifiedAt: Date?
    /// Whether this row is selected for removal.
    public var isSelected: Bool

    public init(
        url: URL,
        label: String,
        category: String,
        confidence: MatchConfidence,
        sizeBytes: Int64? = nil,
        risk: RiskLevel? = nil,
        riskReason: String? = nil,
        modifiedAt: Date? = nil,
        preselected: Bool? = nil
    ) {
        self.id = url
        self.label = label
        self.category = category
        self.confidence = confidence
        let resolvedRisk = risk ?? RiskLevel(confidence: confidence)
        self.risk = resolvedRisk
        self.riskReason = riskReason ?? resolvedRisk.defaultReason
        self.sizeBytes = sizeBytes
        self.modifiedAt = modifiedAt
        // Tough items are NEVER preselected, no matter what a caller asks for:
        // reverting them can be impossible, so opt-in must be explicit and
        // per-item. The invariant lives here, in code, not in scanner discipline.
        let wanted = preselected ?? (confidence == .bundleID)
        self.isSelected = wanted && resolvedRisk != .tough
    }
}

/// An application discovered on disk.
public struct InstalledApp: Identifiable, Sendable, Equatable {
    public var id: URL { bundleURL }
    public let bundleURL: URL
    public let name: String
    public let bundleID: String?
    public var sizeBytes: Int64?

    public init(bundleURL: URL, name: String, bundleID: String?, sizeBytes: Int64? = nil) {
        self.bundleURL = bundleURL
        self.name = name
        self.bundleID = bundleID
        self.sizeBytes = sizeBytes
    }
}

/// A category of removable junk for the Cleanup tab.
public struct CleanupGroup: Identifiable, Sendable, Equatable {
    public var id: String { title }
    public let title: String
    public let subtitle: String
    public var items: [RemovableItem]

    public init(title: String, subtitle: String, items: [RemovableItem]) {
        self.title = title
        self.subtitle = subtitle
        self.items = items
    }

    public var totalBytes: Int64 {
        items.reduce(0) { $0 + ($1.sizeBytes ?? 0) }
    }
    public var selectedBytes: Int64 {
        items.filter(\.isSelected).reduce(0) { $0 + ($1.sizeBytes ?? 0) }
    }
}

/// Outcome of a single Trash move.
public struct RemovalResult: Sendable, Equatable {
    public let url: URL
    public let succeeded: Bool
    public let error: String?

    public init(url: URL, succeeded: Bool, error: String?) {
        self.url = url
        self.succeeded = succeeded
        self.error = error
    }
}
