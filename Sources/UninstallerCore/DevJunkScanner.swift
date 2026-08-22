import Foundation

/// Finds regenerable developer junk: Xcode build products, device-support
/// symbols, stale archives, old simulator devices, package-manager caches, and
/// per-project build artifacts (node_modules, SwiftPM .build).
///
/// Deterministic with respect to the injected `homeRoot` (mirrors
/// `CleanupScanner`), so corecheck can point it at a fixture directory. The
/// clock and staleness cutoffs are injectable via `now:` and `Options` so tests
/// can force either outcome. The project walk is depth-capped and runs under a
/// wall-clock budget so a huge home folder can never hang a scan.
public struct DevJunkScanner: Sendable {

    public struct Options: Sendable {
        /// How many directory levels below each project root are searched for
        /// build artifacts. Found artifacts are never descended into.
        public var projectSearchDepth: Int
        /// Wall-clock budget for the project-artifact walk. The fixed-path
        /// checks (DerivedData, caches, ...) are O(children) and not budgeted.
        public var timeBudget: TimeInterval
        /// An Xcode archive older than this many days is offered as stale.
        public var archiveStaleDays: Int
        /// A simulator device untouched for this many days is offered as old.
        public var simulatorStaleDays: Int

        public init(
            projectSearchDepth: Int = 4,
            timeBudget: TimeInterval = 8,
            archiveStaleDays: Int = 180,
            simulatorStaleDays: Int = 90
        ) {
            self.projectSearchDepth = projectSearchDepth
            self.timeBudget = timeBudget
            self.archiveStaleDays = archiveStaleDays
            self.simulatorStaleDays = simulatorStaleDays
        }
    }

    public struct Scan: Sendable, Equatable {
        public var groups: [CleanupGroup]
        /// Informational findings that are reported but never offered for
        /// removal (Docker.raw), plus any truncation notice from the budgeted
        /// walk. Silent caps would read as "nothing found"; these do not.
        public var notes: [String]

        public init(groups: [CleanupGroup], notes: [String]) {
            self.groups = groups
            self.notes = notes
        }
    }

    /// Home-relative folders treated as project roots for the artifact walk.
    public static let projectRootNames: [String] = [
        "Documents", "Desktop", "Downloads",
        "Projects", "Developer", "dev", "code", "src", "repos", "work",
    ]

    public init() {}

    private var fileManager: FileManager { .default }

    public func scan(
        homeRoot: URL,
        brewCachePath: String? = nil,
        options: Options = Options(),
        now: Date = Date(),
        isCancelled: @Sendable () -> Bool = { false }
    ) -> Scan {
        var notes: [String] = []

        let xcode = xcodeItems(homeRoot: homeRoot, options: options, now: now)
        let caches = packageCacheItems(homeRoot: homeRoot, brewCachePath: brewCachePath)
        let artifacts = projectArtifacts(
            homeRoot: homeRoot, options: options,
            notes: &notes, isCancelled: isCancelled
        )
        if let dockerNote = dockerReport(homeRoot: homeRoot) {
            notes.append(dockerNote)
        }

        return Scan(
            groups: [
                CleanupGroup(
                    title: "Xcode & simulators",
                    subtitle: "DerivedData, device support, stale archives, old simulator devices",
                    items: xcode
                ),
                CleanupGroup(
                    title: "Package manager caches",
                    subtitle: "Homebrew, pip, conda, npm, yarn, pnpm, Gradle, cargo",
                    items: caches
                ),
                CleanupGroup(
                    title: "Project build artifacts",
                    subtitle: "node_modules and SwiftPM .build folders inside your project folders",
                    items: artifacts
                ),
            ],
            notes: notes
        )
    }

    // MARK: - Xcode

    private func xcodeItems(homeRoot: URL, options: Options, now: Date) -> [RemovableItem] {
        var items: [RemovableItem] = []
        let developer = homeRoot.appendingPathComponent("Library/Developer", isDirectory: true)

        // DerivedData: pure build products, rebuilt on the next build. Safe
        // enough to preselect.
        for child in contents(of: developer.appendingPathComponent("Xcode/DerivedData")) {
            guard !LibraryLocations.isProtected(child.lastPathComponent) else { continue }
            items.append(RemovableItem(
                url: child,
                label: "DerivedData/\(child.lastPathComponent)",
                category: "Xcode",
                confidence: .name,
                risk: .easy,
                riskReason: "Regenerable by Xcode: rebuilt automatically on the next build.",
                preselected: true
            ))
        }

        // Device support symbols: regenerated, but only when that device is
        // plugged in again, so a review rather than a preselected easy win.
        for child in contents(of: developer.appendingPathComponent("Xcode/iOS DeviceSupport")) {
            items.append(RemovableItem(
                url: child,
                label: "iOS DeviceSupport/\(child.lastPathComponent)",
                category: "Xcode",
                confidence: .name,
                risk: .review,
                riskReason: "Debug symbols copied from a device; re-created next time that device is connected."
            ))
        }

        // Stale archives: may hold the ONLY dSYMs for builds already shipped,
        // so losing them is permanent. Tough, never preselected.
        let archiveCutoff = now.addingTimeInterval(-Double(options.archiveStaleDays) * 86_400)
        for day in contents(of: developer.appendingPathComponent("Xcode/Archives")) {
            for archive in contents(of: day) {
                guard let modified = modificationDate(of: archive), modified <= archiveCutoff else { continue }
                items.append(RemovableItem(
                    url: archive,
                    label: "Archives/\(day.lastPathComponent)/\(archive.lastPathComponent)",
                    category: "Xcode",
                    confidence: .name,
                    risk: .tough,
                    riskReason: "May hold the only dSYMs for builds you shipped; without them crash reports from those builds stay unreadable.",
                    modifiedAt: modified
                ))
            }
        }

        // Old simulator devices: Xcode recreates devices on demand, but any app
        // data inside them is gone for good.
        let simCutoff = now.addingTimeInterval(-Double(options.simulatorStaleDays) * 86_400)
        for device in contents(of: developer.appendingPathComponent("CoreSimulator/Devices")) {
            guard let modified = modificationDate(of: device), modified <= simCutoff else { continue }
            items.append(RemovableItem(
                url: device,
                label: "CoreSimulator/Devices/\(device.lastPathComponent)",
                category: "Xcode",
                confidence: .name,
                risk: .review,
                riskReason: "A simulator device with its installed apps and data; Xcode recreates the device, the contents are lost.",
                modifiedAt: modified
            ))
        }

        return items
    }

    // MARK: - Package manager caches

    private func packageCacheItems(homeRoot: URL, brewCachePath: String?) -> [RemovableItem] {
        // (candidate path, tool name, home-relative?) tuples. Every one of these
        // is a download cache the tool refills on demand, so they are all easy.
        var candidates: [(url: URL, tool: String)] = []

        if let brewCachePath, !brewCachePath.isEmpty {
            candidates.append((URL(fileURLWithPath: brewCachePath, isDirectory: true), "Homebrew"))
        } else {
            candidates.append((homeRoot.appendingPathComponent("Library/Caches/Homebrew"), "Homebrew"))
        }
        candidates.append((homeRoot.appendingPathComponent(".cache/pip"), "pip"))
        for condaBase in ["miniconda3", "anaconda3", "miniforge3", "mambaforge",
                          "opt/miniconda3", "opt/anaconda3"] {
            candidates.append((homeRoot.appendingPathComponent("\(condaBase)/pkgs"), "conda"))
        }
        let npmCacache = homeRoot.appendingPathComponent(".npm/_cacache")
        if isDirectory(npmCacache) {
            candidates.append((npmCacache, "npm"))
        } else {
            candidates.append((homeRoot.appendingPathComponent(".npm"), "npm"))
        }
        candidates.append((homeRoot.appendingPathComponent("Library/Caches/Yarn"), "yarn"))
        candidates.append((homeRoot.appendingPathComponent(".cache/yarn"), "yarn"))
        candidates.append((homeRoot.appendingPathComponent("Library/pnpm/store"), "pnpm"))
        candidates.append((homeRoot.appendingPathComponent(".local/share/pnpm/store"), "pnpm"))
        candidates.append((homeRoot.appendingPathComponent(".pnpm-store"), "pnpm"))
        candidates.append((homeRoot.appendingPathComponent(".gradle/caches"), "Gradle"))
        candidates.append((homeRoot.appendingPathComponent(".cargo/registry/cache"), "cargo"))

        var items: [RemovableItem] = []
        var seen = Set<URL>()
        for candidate in candidates {
            let url = candidate.url.standardizedFileURL
            guard isDirectory(url), !seen.contains(url) else { continue }
            seen.insert(url)
            items.append(RemovableItem(
                url: url,
                label: "\(candidate.tool): \(displayPath(url, homeRoot: homeRoot))",
                category: "Package caches",
                confidence: .name,
                risk: .easy,
                riskReason: "Regenerable: \(candidate.tool) re-downloads anything a build needs.",
                preselected: true
            ))
        }
        return items
    }

    // MARK: - Project build artifacts

    private func projectArtifacts(
        homeRoot: URL,
        options: Options,
        notes: inout [String],
        isCancelled: @Sendable () -> Bool
    ) -> [RemovableItem] {
        var items: [RemovableItem] = []
        var truncated = false
        let deadline = Date().addingTimeInterval(options.timeBudget)

        for rootName in Self.projectRootNames {
            let root = homeRoot.appendingPathComponent(rootName, isDirectory: true)
            guard isDirectory(root) else { continue }
            walk(root, homeRoot: homeRoot, depth: 0, options: options,
                 deadline: deadline, into: &items, truncated: &truncated,
                 isCancelled: isCancelled)
        }

        if truncated {
            notes.append("The project folder walk stopped at its time budget; some build artifacts may not be listed. Rescan to look again.")
        }
        return items
    }

    private func walk(
        _ dir: URL,
        homeRoot: URL,
        depth: Int,
        options: Options,
        deadline: Date,
        into items: inout [RemovableItem],
        truncated: inout Bool,
        isCancelled: @Sendable () -> Bool
    ) {
        if Date() >= deadline || isCancelled() {
            truncated = true
            return
        }
        // Do NOT skip hidden entries wholesale: `.build` is hidden and is
        // exactly what we are looking for. Hidden trees are skipped below,
        // after the artifact checks.
        guard let children = try? fileManager.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: []
        ) else { return }

        for child in children {
            if Date() >= deadline || isCancelled() {
                truncated = true
                return
            }
            let values = try? child.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            // Symlinks are never followed: they can escape the project root or
            // form cycles.
            guard values?.isDirectory == true, values?.isSymbolicLink != true else { continue }

            let name = child.lastPathComponent
            if name == "node_modules" {
                items.append(RemovableItem(
                    url: child,
                    label: displayPath(child, homeRoot: homeRoot),
                    category: "Build artifacts",
                    confidence: .name,
                    risk: .easy,
                    riskReason: "Regenerable: npm, yarn, or pnpm install restores it from the lockfile."
                ))
                continue                        // never descend into a found artifact
            }
            if name == ".build",
               fileManager.fileExists(atPath: dir.appendingPathComponent("Package.swift").path) {
                items.append(RemovableItem(
                    url: child,
                    label: displayPath(child, homeRoot: homeRoot),
                    category: "Build artifacts",
                    confidence: .name,
                    risk: .easy,
                    riskReason: "Regenerable: swift build recreates it."
                ))
                continue
            }
            if name.hasPrefix(".") { continue } // other hidden trees (git, venvs)
            if name == "Library" || name == "node_modules" { continue }
            if depth + 1 <= options.projectSearchDepth {
                walk(child, homeRoot: homeRoot, depth: depth + 1, options: options,
                     deadline: deadline, into: &items, truncated: &truncated,
                     isCancelled: isCancelled)
            }
        }
    }

    // MARK: - Docker

    /// Docker.raw is reported, never offered: deleting it destroys every
    /// container and volume, and shrinking it is a Docker Desktop operation.
    private func dockerReport(homeRoot: URL) -> String? {
        let raw = homeRoot.appendingPathComponent(
            "Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw")
        guard fileManager.fileExists(atPath: raw.path) else { return nil }
        let values = try? raw.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey])
        let bytes = Int64(values?.totalFileAllocatedSize ?? values?.fileAllocatedSize ?? 0)
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        let size = bytes > 0 ? formatter.string(fromByteCount: bytes) : "an unknown amount"
        return "Docker.raw uses \(size) at ~/Library/Containers/com.docker.docker. Shrink it from Docker Desktop (Settings, Resources); deleting the file would destroy all containers and volumes, so it is not offered here."
    }

    // MARK: - Homebrew detection

    /// Ask brew itself where its cache is (`brew --cache`). Returns nil when
    /// Homebrew is not installed; the scanner then falls back to the default
    /// cache location. Runs a subprocess, so call it off the main actor.
    public static func detectBrewCachePath() -> String? {
        for brew in ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]
        where FileManager.default.isExecutableFile(atPath: brew) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: brew)
            process.arguments = ["--cache"]
            let out = Pipe()
            process.standardOutput = out
            process.standardError = FileHandle.nullDevice
            do { try process.run() } catch { continue }
            let data = out.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { continue }
            let path = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !path.isEmpty { return path }
        }
        return nil
    }

    // MARK: - Helpers

    private func contents(of dir: URL) -> [URL] {
        (try? fileManager.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []
    }

    private func isDirectory(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }

    private func modificationDate(of url: URL) -> Date? {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }

    private func displayPath(_ url: URL, homeRoot: URL) -> String {
        let home = homeRoot.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        if path.hasPrefix(home + "/") {
            return "~" + String(path.dropFirst(home.count))
        }
        return path
    }
}
