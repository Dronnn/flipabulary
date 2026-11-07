import Foundation

enum ImportFormat: String, Sendable {
    case csv
    case anki
}

struct ImportedCard: Equatable, Sendable {
    var word: String
    var translation: String
    var example: String?
    var translatedExample: String?
    var phonetic: String?
    var partOfSpeech: String?
    var tags: [String]
}

struct ImportedDeck: Equatable, Sendable {
    var name: String
    var cards: [ImportedCard]
}

struct ImportPlan: Equatable, Sendable, Identifiable {
    var format: ImportFormat
    var sourceName: String
    var decks: [ImportedDeck]
    var skippedRows: Int
    var usesDeckNames: Bool

    var id: String {
        "\(format.rawValue)-\(sourceName)-\(totalCards)-\(decks.count)"
    }

    var totalCards: Int {
        decks.reduce(0) { $0 + $1.cards.count }
    }

    var suggestedStackName: String {
        decks.first?.name ?? "Imported words"
    }
}

struct ImportSummary: Equatable, Sendable {
    var imported: Int
    var skipped: Int
    var stacks: [String]
}

enum ImportExportError: Error, Equatable {
    case unreadableFile
    case invalidCSV
    case noValidRows
    case modernAnki
    case invalidAnki
    case unsupportedArchive
    case emptyStack
}
