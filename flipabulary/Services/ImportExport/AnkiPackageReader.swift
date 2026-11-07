import Foundation
import SQLite3

enum AnkiPackageReader {
    static func parse(data: Data, fileName: String) throws -> ImportPlan {
        let archive: ZIPArchiveReader
        do {
            archive = try ZIPArchiveReader(data: data)
        } catch {
            throw ImportExportError.unsupportedArchive
        }

        if archive.contains("collection.anki21b") {
            throw ImportExportError.modernAnki
        }

        let collectionName: String
        if archive.contains("collection.anki21") {
            collectionName = "collection.anki21"
        } else if archive.contains("collection.anki2") {
            collectionName = "collection.anki2"
        } else {
            throw ImportExportError.invalidAnki
        }

        let collectionData: Data
        do {
            collectionData = try archive.data(for: collectionName)
        } catch {
            throw ImportExportError.unsupportedArchive
        }

        let temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("flipabulary-import-\(UUID().uuidString).sqlite")
        try collectionData.write(to: temporaryURL, options: .atomic)
        defer { try? FileManager.default.removeItem(at: temporaryURL) }

        let database: SQLiteDatabase
        do {
            database = try SQLiteDatabase(path: temporaryURL.path)
        } catch {
            throw ImportExportError.invalidAnki
        }

        guard let row = try database.rows("SELECT decks, models FROM col LIMIT 1").first,
              let decksJSON = row[safe: 0] ?? nil,
              let modelsJSON = row[safe: 1] ?? nil,
              let decksObject = decodeJSONObject(decksJSON),
              let models = decodeJSONObject(modelsJSON) else {
            throw ImportExportError.invalidAnki
        }

        let deckNames = deckNames(from: decksObject)
        let fieldNames = modelFieldNames(from: models)
        let noteRows: [[String?]]
        do {
            noteRows = try database.rows("""
                SELECT n.id, n.mid, n.flds, n.tags, MIN(c.did) AS did
                FROM notes n
                JOIN cards c ON c.nid = n.id
                GROUP BY n.id
                ORDER BY n.id
                """)
        } catch {
            throw ImportExportError.invalidAnki
        }

        var decksByName: [String: [ImportedCard]] = [:]
        var deckOrder: [String] = []
        var skipped = 0

        for note in noteRows {
            guard let mid = note[safe: 1] ?? nil,
                  let fieldsValue = note[safe: 2] ?? nil,
                  let deckID = note[safe: 4] ?? nil else {
                skipped += 1
                continue
            }
            let tags = (note[safe: 3] ?? nil)?
                .split(whereSeparator: \.isWhitespace)
                .map(String.init) ?? []
            let fieldList = fieldsValue.components(separatedBy: "\u{1f}").map(HTMLText.clean)
            let names = fieldNames[mid] ?? []

            guard let card = makeCard(
                fields: fieldList,
                fieldNames: names,
                tags: tags
            ) else {
                skipped += 1
                continue
            }

            let rawDeckName = deckNames[deckID] ?? "Imported deck"
            let deckName = displayDeckName(rawDeckName)
            if decksByName[deckName] == nil {
                deckOrder.append(deckName)
                decksByName[deckName] = []
            }
            decksByName[deckName]?.append(card)
        }

        let importedDecks = deckOrder.compactMap { name -> ImportedDeck? in
            guard let cards = decksByName[name], !cards.isEmpty else { return nil }
            return ImportedDeck(name: name, cards: cards)
        }
        guard importedDecks.contains(where: { !$0.cards.isEmpty }) else {
            throw ImportExportError.noValidRows
        }

        return ImportPlan(
            format: .anki,
            sourceName: fileName,
            decks: importedDecks,
            skippedRows: skipped,
            usesDeckNames: true
        )
    }

    private static func makeCard(
        fields: [String],
        fieldNames: [String],
        tags: [String]
    ) -> ImportedCard? {
        guard !fields.isEmpty else { return nil }

        func index(for synonyms: [String]) -> Int? {
            for (index, name) in fieldNames.enumerated() {
                let normalized = normalizeName(name)
                if synonyms.contains(where: { normalized.contains($0) }) {
                    return index
                }
            }
            return nil
        }

        let wordIndex = index(for: ["word", "front", "term", "question", "prompt", "expression", "phrase"]) ?? 0
        let translationIndex = index(for: ["translation", "back", "definition", "answer", "meaning", "target"])
            ?? (fields.count > 1 ? 1 : nil)
        guard fields.indices.contains(wordIndex),
              let translationIndex,
              fields.indices.contains(translationIndex) else {
            return nil
        }

        let word = fields[wordIndex]
        let translation = fields[translationIndex]
        guard !word.isEmpty, !translation.isEmpty,
              word.count <= 200, translation.count <= 200 else {
            return nil
        }

        let exampleIndex = index(for: ["example", "sentence", "usage", "context"])
        let translatedExampleIndex = index(for: ["translated example", "example translation", "target example"])
        let phoneticIndex = index(for: ["phonetic", "pronunciation", "ipa", "reading", "transcription"])
        let partOfSpeechIndex = index(for: ["part of speech", "pos", "type"])

        func value(_ index: Int?) -> String? {
            guard let index, fields.indices.contains(index) else { return nil }
            let value = fields[index]
            return value.isEmpty ? nil : value
        }

        return ImportedCard(
            word: word,
            translation: translation,
            example: value(exampleIndex),
            translatedExample: value(translatedExampleIndex),
            phonetic: value(phoneticIndex),
            partOfSpeech: value(partOfSpeechIndex),
            tags: cleanTags(tags)
        )
    }

    private static func deckNames(from decks: [String: Any]) -> [String: String] {
        var result: [String: String] = [:]
        for (key, value) in decks {
            guard let deck = value as? [String: Any] else { continue }
            if let name = deck["name"] as? String {
                result[key] = name
            }
        }
        return result
    }

    private static func modelFieldNames(from models: [String: Any]) -> [String: [String]] {
        var result: [String: [String]] = [:]
        for (key, value) in models {
            guard let model = value as? [String: Any],
                  let fields = model["flds"] as? [[String: Any]] else { continue }
            result[key] = fields.compactMap { $0["name"] as? String }
        }
        return result
    }

    private static func decodeJSONObject(_ string: String) -> [String: Any]? {
        guard let data = string.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private static func displayDeckName(_ raw: String) -> String {
        let cleaned = raw
            .replacingOccurrences(of: "::", with: " · ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Imported deck" : String(cleaned.prefix(60))
    }

    private static func normalizeName(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func cleanTags(_ tags: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for tag in tags {
            let trimmed = String(tag.trimmingCharacters(in: .whitespacesAndNewlines).prefix(60))
            guard !trimmed.isEmpty else { continue }
            let key = trimmed.lowercased()
            guard seen.insert(key).inserted else { continue }
            result.append(trimmed)
        }
        return result
    }
}

enum HTMLText {
    static func clean(_ raw: String) -> String {
        var text = raw
        text = text.replacingOccurrences(of: "(?is)<(script|style)[^>]*>.*?</\\1>", with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: "(?i)<br\\s*/?>", with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "(?i)</(div|p|li|tr|h[1-6])>", with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: "\\[sound:[^\\]]+\\]", with: " ", options: .regularExpression)
        text = stripCloze(text)
        text = decodeEntities(text)
        text = text.replacingOccurrences(of: "[\\t ]+", with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: " *\\n *", with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "\\n{2,}", with: "\n", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func stripCloze(_ text: String) -> String {
        text.replacingOccurrences(
            of: "\\{\\{c\\d+::([^{}]*?)(?:::[^{}]*?)?\\}\\}",
            with: "$1",
            options: .regularExpression
        )
    }

    private static func decodeEntities(_ text: String) -> String {
        let entities = [
            "&nbsp;": " ",
            "&iquest;": "¿",
            "&iexcl;": "¡",
            "&amp;": "&",
            "&lt;": "<",
            "&gt;": ">",
            "&quot;": "\"",
            "&#39;": "'",
            "&apos;": "'",
            "&mdash;": "—",
            "&ndash;": "–",
            "&hellip;": "…",
            "&rsquo;": "’",
            "&lsquo;": "‘",
            "&ldquo;": "“",
            "&rdquo;": "”",
            "&eacute;": "é",
            "&egrave;": "è",
            "&agrave;": "à",
            "&ccedil;": "ç",
            "&uuml;": "ü",
            "&ouml;": "ö",
            "&auml;": "ä",
            "&szlig;": "ß",
            "&ntilde;": "ñ",
            "&aacute;": "á",
            "&iacute;": "í",
            "&oacute;": "ó",
            "&uacute;": "ú"
        ]
        var result = text
        for (entity, replacement) in entities {
            result = result.replacingOccurrences(of: entity, with: replacement)
        }
        return result
    }
}

private final class SQLiteDatabase {
    private var handle: OpaquePointer?

    init(path: String) throws {
        guard sqlite3_open_v2(path, &handle, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            if let handle { sqlite3_close(handle) }
            throw ImportExportError.invalidAnki
        }
    }

    deinit {
        if let handle { sqlite3_close(handle) }
    }

    func rows(_ sql: String) throws -> [[String?]] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
            throw ImportExportError.invalidAnki
        }
        defer { sqlite3_finalize(statement) }

        var rows: [[String?]] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { break }
            guard result == SQLITE_ROW else { throw ImportExportError.invalidAnki }
            let count = sqlite3_column_count(statement)
            var row: [String?] = []
            for index in 0..<count {
                if sqlite3_column_type(statement, index) == SQLITE_NULL {
                    row.append(nil)
                } else if let text = sqlite3_column_text(statement, index) {
                    row.append(String(cString: text))
                } else {
                    row.append(nil)
                }
            }
            rows.append(row)
        }
        return rows
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
