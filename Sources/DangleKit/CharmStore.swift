import Foundation

/// A charm is a small JSON file: an id, a display name, and the CharmSpec to
/// splice into the active pack. The app ships with only the `</>` charm; new
/// ones are published to the project repository and installed from the menu
/// bar — no app update required.
public struct Charm: Codable, Equatable {
    public var id: String
    public var name: String
    public var charm: DanglePack.CharmSpec
    /// This charm's own notes, shown instead of the pack's while it hangs.
    /// nil falls back to the pack's notes.
    public var notes: [String]?

    public init(id: String, name: String, charm: DanglePack.CharmSpec, notes: [String]? = nil) {
        self.id = id
        self.name = name
        self.charm = charm
        self.notes = notes
    }

    /// Ids double as filenames and URL components; keep them boring.
    public static func isValidID(_ id: String) -> Bool {
        !id.isEmpty && id.count <= 64 && id.allSatisfy {
            $0.isLowercase && $0.isASCII || $0.isNumber && $0.isASCII || $0 == "-"
        }
    }
}

/// The published charm catalog: `charms/index.json` in the repository.
public struct CharmIndex: Codable {
    public var charms: [Entry]

    public struct Entry: Codable {
        public var id: String
        public var name: String
        /// File name of the charm JSON, relative to the index URL.
        public var file: String
    }
}

/// What a catalog fetch produced: charms actually installed, plus how many
/// catalog entries could not be fetched or were rejected.
public struct CharmFetchResult {
    public var added: [Charm]
    public var failedCount: Int
}

/// Installs and lists charms. Installed charms live as JSON files in
/// Application Support; the catalog is only fetched when the user asks.
public final class CharmStore {

    public static let shared = CharmStore()

    /// Where the published catalog lives by default. Overridable per instance
    /// for tests, and via DANGLE_CHARM_INDEX for forks.
    public static var defaultIndexURL: URL {
        if let env = ProcessInfo.processInfo.environment["DANGLE_CHARM_INDEX"] {
            if let url = URL(string: env), url.scheme != nil { return url }
            return URL(fileURLWithPath: env)
        }
        return URL(string: "https://raw.githubusercontent.com/Melvin0070/dangle/main/charms/index.json")!
    }

    private let directory: URL
    private let indexURL: URL
    private var isFetching = false

    public init(directory: URL? = nil, indexURL: URL? = nil) {
        if let directory {
            self.directory = directory
        } else {
            let appSupport = FileManager.default.urls(
                for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            self.directory = appSupport.appendingPathComponent("Dangle/Charms")
        }
        self.indexURL = indexURL ?? Self.defaultIndexURL
    }

    public func installedCharms() -> [Charm] {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: directory,
                                                      includingPropertiesForKeys: nil)
        else { return [] }
        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { try? JSONDecoder().decode(Charm.self, from: Data(contentsOf: $0)) }
            .filter { Charm.isValidID($0.id) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    public func charm(id: String) -> Charm? {
        installedCharms().first { $0.id == id }
    }

    /// Copies any charms bundled with the app (Contents/Resources/Charms/)
    /// into the installed directory, skipping ones already there. Called
    /// once at startup so the default charm set is available immediately —
    /// no "Get New Charms…" fetch needed for what ships with the app.
    public func seedBundledCharms() {
        guard let resourceURL = Bundle.main.resourceURL else { return }
        let bundledDir = resourceURL.appendingPathComponent("Charms")
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: bundledDir,
                                                       includingPropertiesForKeys: nil)
        else { return }
        let installedIDs = Set(installedCharms().map(\.id))
        for url in files where url.pathExtension == "json" {
            guard let data = try? Data(contentsOf: url),
                  let charm = try? JSONDecoder().decode(Charm.self, from: data),
                  !installedIDs.contains(charm.id)
            else { continue }
            try? install(charm)
        }
    }

    public func install(_ charm: Charm) throws {
        guard Charm.isValidID(charm.id) else {
            throw CocoaError(.fileWriteInvalidFileName)
        }
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(charm)
        // Atomic: installedCharms() may be reading on another thread.
        try data.write(to: directory.appendingPathComponent("\(charm.id).json"),
                       options: .atomic)
    }

    /// Fetches the catalog and installs anything not already installed.
    /// Calls back on the main queue.
    public func fetchNewCharms(completion: @escaping (Result<CharmFetchResult, Error>) -> Void) {
        // One fetch at a time; a second click while in flight is a no-op.
        guard !isFetching else { return }
        isFetching = true
        let installed = Set(installedCharms().map(\.id))
        let indexURL = self.indexURL
        let finish: (Result<CharmFetchResult, Error>) -> Void = { [weak self] result in
            DispatchQueue.main.async {
                self?.isFetching = false
                completion(result)
            }
        }
        URLSession.shared.dataTask(with: indexURL) { data, response, error in
            if let error { return finish(.failure(error)) }
            guard let data, Self.isAcceptable(response) else {
                return finish(.failure(URLError(.badServerResponse)))
            }
            let index: CharmIndex
            do {
                index = try JSONDecoder().decode(CharmIndex.self, from: data)
            } catch {
                return finish(.failure(error))
            }
            let base = indexURL.deletingLastPathComponent()
            let fresh = index.charms.filter {
                !installed.contains($0.id) && Charm.isValidID($0.id)
            }
            guard !fresh.isEmpty else {
                return finish(.success(CharmFetchResult(added: [], failedCount: 0)))
            }
            var added: [Charm] = []
            var failed = 0
            let lock = NSLock()
            let group = DispatchGroup()
            for entry in fresh {
                group.enter()
                let url = base.appendingPathComponent(entry.file)
                URLSession.shared.dataTask(with: url) { data, response, _ in
                    defer { group.leave() }
                    lock.lock()
                    defer { lock.unlock() }
                    guard let data, Self.isAcceptable(response),
                          let charm = try? JSONDecoder().decode(Charm.self, from: data),
                          // The file must be the charm the catalog promised.
                          charm.id == entry.id,
                          (try? self.install(charm)) != nil
                    else {
                        failed += 1
                        return
                    }
                    added.append(charm)
                }.resume()
            }
            group.notify(queue: .main) {
                added.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                finish(.success(CharmFetchResult(added: added, failedCount: failed)))
            }
        }.resume()
    }

    /// file:// loads have no HTTP response; anything else must be a 2xx.
    private static func isAcceptable(_ response: URLResponse?) -> Bool {
        guard let http = response as? HTTPURLResponse else { return true }
        return (200..<300).contains(http.statusCode)
    }
}
