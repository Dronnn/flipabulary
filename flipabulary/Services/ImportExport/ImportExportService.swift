import Foundation

enum ImportExportService {
    // MARK: Import

    static func parseCSV(data: Data, fileName: String) throws -> ImportPlan {
        guard let text = decodeText(data) else {
            throw ImportExportError.unreadableFile
        }
        let table = CSVParser.parse(text)
        guard !table.rows.isEmpty else {
            throw ImportExportError.invalidCSV
        }

        let columns = detectColumns(in: table.rows[0])
        let hasHeader = columns.hasHeader
        let dataRows = hasHeader ? Array(table.rows.dropFirst()) : table.rows
        let baseName = defaultStackName(from: fileName)

        var decks: [String: [ImportedCard]] = [:]
        var order: [String] = []
        var skipped = 0

        for row in dataRows {
            guard let card = makeCard(from: row, columns: columns) else {
                skipped += 1
                continue
            }
            let deckName: String
            if let stackIndex = columns.stack, row.indices.contains(stackIndex) {
                let raw = row[stackIndex].trimmingCharacters(in: .whitespacesAndNewlines)
                deckName = raw.isEmpty ? baseName : String(raw.prefix(60))
            } else {
                deckName = baseName
            }
            if decks[deckName] == nil {
                order.append(deckName)
                decks[deckName] = []
            }
            decks[deckName]?.append(card)
        }

        let importedDecks = order.compactMap { name -> ImportedDeck? in
            guard let cards = decks[name], !cards.isEmpty else { return nil }
            return ImportedDeck(name: name, cards: cards)
        }
        guard !importedDecks.isEmpty else {
            throw ImportExportError.noValidRows
        }

        return ImportPlan(
            format: .csv,
            sourceName: fileName,
            decks: importedDecks,
            skippedRows: skipped,
            usesDeckNames: columns.stack != nil
        )
    }

    static func parseAnki(data: Data, fileName: String) throws -> ImportPlan {
        try AnkiPackageReader.parse(data: data, fileName: fileName)
    }

    // MARK: Export

    static func exportCSV(stack: VocabularyStack) -> Data {
        var rows: [[String]] = [[
            "Word",
            "Translation",
            "Example",
            "Translated example",
            "Phonetic",
            "Part of speech",
            "Tags"
        ]]
        for card in stack.cards.sorted(by: { $0.createdAt < $1.createdAt }) {
            rows.append([
                card.word,
                card.translation,
                card.sourceExample ?? "",
                card.translatedExample ?? "",
                card.phonetic ?? "",
                card.partOfSpeech ?? "",
                card.tags.map(\.name).sorted().joined(separator: "; ")
            ])
        }
        return CSVWriter.data(rows: rows)
    }

    static func exportAnkiText(stack: VocabularyStack) -> Data {
        var lines = [
            "#separator:tab",
            "#html:false",
            "#tags column:3"
        ]
        for card in stack.cards.sorted(by: { $0.createdAt < $1.createdAt }) {
            let word = cleanTabField(card.word)
            let translation = cleanTabField(card.translation)
            let tags = card.tags.map(\.name).sorted().joined(separator: " ")
            lines.append("\(word)\t\(translation)\t\(tags)")
        }
        return Data((lines.joined(separator: "\n") + "\n").utf8)
    }

    static func exportPlainText(stack: VocabularyStack) -> Data {
        let lines = stack.cards
            .sorted(by: { $0.createdAt < $1.createdAt })
            .map { "\(cleanTabField($0.word))\t\(cleanTabField($0.translation))" }
        return Data((lines.joined(separator: "\n") + "\n").utf8)
    }

    // MARK: CSV helpers

    private struct CSVColumns {
        var word: Int?
        var translation: Int?
        var example: Int?
        var translatedExample: Int?
        var phonetic: Int?
        var partOfSpeech: Int?
        var tags: Int?
        var stack: Int?
        var hasHeader: Bool
    }

    private static func detectColumns(in firstRow: [String]) -> CSVColumns {
        let normalized = firstRow.map(normalizeHeader)
        func index(of synonyms: [String]) -> Int? {
            normalized.firstIndex { value in
                synonyms.contains { value == $0 || value.contains($0) }
            }
        }

        let word = index(of: ["word", "front", "term", "question", "prompt", "source", "expression", "phrase"])
        let translation = index(of: ["translation", "back", "definition", "answer", "meaning", "target"])
        let example = index(of: ["example", "sentence", "usage", "context", "notes", "note"])
        let translatedExample = index(of: ["translated example", "example translation", "target example", "translation example"])
        let phonetic = index(of: ["phonetic", "pronunciation", "ipa", "reading", "transcription"])
        let partOfSpeech = index(of: ["part of speech", "pos", "type", "category"])
        let tags = index(of: ["tags", "tag", "keywords", "keyword"])
        let stack = index(of: ["stack", "deck", "list", "folder", "set"])

        let matched = [word, translation, example, translatedExample, phonetic, partOfSpeech, tags, stack]
            .compactMap { $0 }
            .count
        let hasHeader = matched >= 2 && word != nil && translation != nil

        if hasHeader {
            return CSVColumns(
                word: word,
                translation: translation,
                example: example,
                translatedExample: translatedExample,
                phonetic: phonetic,
                partOfSpeech: partOfSpeech,
                tags: tags,
                stack: stack,
                hasHeader: true
            )
        }

        return CSVColumns(
            word: 0,
            translation: 1,
            example: 2,
            translatedExample: 3,
            phonetic: 4,
            partOfSpeech: 5,
            tags: 6,
            stack: nil,
            hasHeader: false
        )
    }

    private static func makeCard(
        from row: [String],
        columns: CSVColumns
    ) -> ImportedCard? {
        func value(_ index: Int?) -> String? {
            guard let index, row.indices.contains(index) else { return nil }
            let cleaned = HTMLText.clean(row[index])
            return cleaned.isEmpty ? nil : cleaned
        }

        guard let word = value(columns.word),
              let translation = value(columns.translation),
              word.count <= 200,
              translation.count <= 200 else {
            return nil
        }

        let tags = value(columns.tags)?.components(separatedBy: CharacterSet(charactersIn: ",;|").union(.whitespacesAndNewlines)) ?? []

        return ImportedCard(
            word: word,
            translation: translation,
            example: value(columns.example).map { String($0.prefix(2_000)) },
            translatedExample: value(columns.translatedExample).map { String($0.prefix(2_000)) },
            phonetic: value(columns.phonetic).map { String($0.prefix(200)) },
            partOfSpeech: value(columns.partOfSpeech).map { String($0.prefix(60)) },
            tags: cleanTags(tags)
        )
    }

    private static func decodeText(_ data: Data) -> String? {
        if data.starts(with: [0xEF, 0xBB, 0xBF]) {
            return String(data: data.dropFirst(3), encoding: .utf8)
        }
        if data.starts(with: [0xFF, 0xFE]) {
            return String(data: data, encoding: .utf16LittleEndian)
        }
        if data.starts(with: [0xFE, 0xFF]) {
            return String(data: data, encoding: .utf16BigEndian)
        }
        return String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
    }

    private static func defaultStackName(from fileName: String) -> String {
        let name = (fileName as NSString).deletingPathExtension
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return String((trimmed.isEmpty ? "Imported words" : trimmed).prefix(60))
    }

    private static func normalizeHeader(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func cleanTags(_ raw: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for tag in raw {
            let trimmed = String(tag.trimmingCharacters(in: .whitespacesAndNewlines).prefix(60))
            guard !trimmed.isEmpty else { continue }
            let key = trimmed.lowercased()
            guard seen.insert(key).inserted else { continue }
            result.append(trimmed)
        }
        return result
    }

    private static func cleanTabField(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\t", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
    }
}
