import Foundation

struct WidgetSnapshotStore: Sendable {
    static let appGroupID = "group.com.mrmaier.flipabulary"
    static let fileName = "widget-snapshot.json"
    static let defaultsKey = "flipabulary.widgetSnapshot.v1"

    static let shared = WidgetSnapshotStore()

    let fileURL: URL?
    private let defaultsSuiteName: String?
    private let defaultsKeyOverride: String?

    init() {
        let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Self.appGroupID)
        fileURL = container?.appendingPathComponent(Self.fileName, isDirectory: false)
        defaultsSuiteName = Self.appGroupID
        defaultsKeyOverride = nil
    }

    init(fileURL: URL?, defaultsSuiteName: String?, defaultsKey: String? = nil) {
        self.fileURL = fileURL
        self.defaultsSuiteName = defaultsSuiteName
        self.defaultsKeyOverride = defaultsKey
    }

    private var defaults: UserDefaults? {
        defaultsSuiteName.flatMap(UserDefaults.init(suiteName:))
    }

    private var key: String { defaultsKeyOverride ?? Self.defaultsKey }

    func save(_ snapshot: WidgetSnapshot) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(snapshot)

        if let fileURL {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: fileURL, options: .atomic)
        }
        defaults?.set(data, forKey: key)
    }

    func load() -> WidgetSnapshot? {
        if let fileURL,
           let fileData = try? Data(contentsOf: fileURL),
           let snapshot = decode(fileData) {
            return snapshot
        }
        if let defaultsData = defaults?.data(forKey: key), let snapshot = decode(defaultsData) {
            return snapshot
        }
        return nil
    }

    private func decode(_ data: Data) -> WidgetSnapshot? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let snapshot = try? decoder.decode(WidgetSnapshot.self, from: data) else { return nil }
        guard snapshot.schemaVersion <= WidgetSnapshot.currentSchemaVersion else { return nil }
        return snapshot
    }

    func clear() {
        if let fileURL {
            try? FileManager.default.removeItem(at: fileURL)
        }
        defaults?.removeObject(forKey: key)
    }
}
