import Foundation

enum CSVDelimiter: Character, CaseIterable, Sendable {
    case comma = ","
    case tab = "\t"
    case semicolon = ";"
    case pipe = "|"

    var displayName: String {
        switch self {
        case .comma: "comma"
        case .tab: "tab"
        case .semicolon: "semicolon"
        case .pipe: "pipe"
        }
    }
}

struct CSVTable: Equatable, Sendable {
    var rows: [[String]]
    var delimiter: CSVDelimiter
}

enum CSVParser {
    static func parse(_ text: String) -> CSVTable {
        let cleaned = stripBOM(text)
        let delimiter = detectDelimiter(in: cleaned)
        return CSVTable(rows: parseRows(cleaned, delimiter: delimiter.rawValue), delimiter: delimiter)
    }

    static func stripBOM(_ text: String) -> String {
        text.hasPrefix("\u{feff}") ? String(text.dropFirst()) : text
    }

    static func detectDelimiter(in text: String) -> CSVDelimiter {
        let lines = text.split(whereSeparator: \.isNewline).prefix(8)
        var best = CSVDelimiter.comma
        var bestScore = 0
        for candidate in CSVDelimiter.allCases {
            var score = 0
            for line in lines {
                score += countDelimiter(candidate.rawValue, in: String(line))
            }
            if score > bestScore {
                bestScore = score
                best = candidate
            }
        }
        return best
    }

    private static func countDelimiter(_ delimiter: Character, in line: String) -> Int {
        var count = 0
        var inQuotes = false
        var index = line.startIndex
        while index < line.endIndex {
            let character = line[index]
            if character == "\"" {
                let next = line.index(after: index)
                if inQuotes, next < line.endIndex, line[next] == "\"" {
                    index = line.index(after: next)
                    continue
                }
                inQuotes.toggle()
            } else if character == delimiter, !inQuotes {
                count += 1
            }
            index = line.index(after: index)
        }
        return count
    }

    static func parseRows(_ text: String, delimiter: Character) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var index = text.startIndex

        func endField() {
            row.append(field)
            field = ""
        }

        func endRow() {
            endField()
            rows.append(row)
            row = []
        }

        while index < text.endIndex {
            let character = text[index]
            if inQuotes {
                if character == "\"" {
                    let next = text.index(after: index)
                    if next < text.endIndex, text[next] == "\"" {
                        field.append("\"")
                        index = text.index(after: next)
                        continue
                    }
                    inQuotes = false
                } else {
                    field.append(character)
                }
            } else if character == "\"", field.isEmpty {
                inQuotes = true
            } else if character == delimiter {
                endField()
            } else if character == "\n" {
                endRow()
            } else if character == "\r" {
                let next = text.index(after: index)
                if next < text.endIndex, text[next] == "\n" {
                    index = next
                }
                endRow()
            } else {
                field.append(character)
            }
            index = text.index(after: index)
        }

        if !field.isEmpty || !row.isEmpty {
            endRow()
        }
        return rows.filter { row in
            row.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        }
    }
}

enum CSVWriter {
    static func write(rows: [[String]]) -> String {
        rows.map { row in
            row.map(escape).joined(separator: ",")
        }.joined(separator: "\r\n") + "\r\n"
    }

    static func data(rows: [[String]]) -> Data {
        let text = write(rows: rows)
        var data = Data([0xEF, 0xBB, 0xBF])
        data.append(Data(text.utf8))
        return data
    }

    static func escape(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") || value.contains("\r") || value.hasPrefix(" ") || value.hasSuffix(" ") {
            return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return value
    }
}
