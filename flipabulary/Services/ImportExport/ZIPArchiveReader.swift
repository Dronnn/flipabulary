import Compression
import Foundation

enum ZIPArchiveError: Error {
    case invalidArchive
    case unsupportedCompression
    case encrypted
    case sizeLimit
}

struct ZIPArchiveReader {
    private struct Entry {
        var name: String
        var method: UInt16
        var flags: UInt16
        var compressedSize: Int
        var uncompressedSize: Int
        var localHeaderOffset: Int
    }

    private let data: Data
    private let entries: [String: Entry]
    private let maxEntrySize = 200 * 1024 * 1024

    init(data: Data) throws {
        self.data = data
        guard let eocd = Self.findEndOfCentralDirectory(in: data) else {
            throw ZIPArchiveError.invalidArchive
        }
        guard let entryCount = data.uint16(at: eocd + 10),
              let centralOffset = data.uint32(at: eocd + 16) else {
            throw ZIPArchiveError.invalidArchive
        }
        guard entryCount != 0xFFFF, centralOffset != 0xFFFF_FFFF else {
            throw ZIPArchiveError.invalidArchive
        }

        var entries: [String: Entry] = [:]
        var cursor = Int(centralOffset)
        for _ in 0..<Int(entryCount) {
            guard data.uint32(at: cursor) == 0x0201_4b50,
                  let flags = data.uint16(at: cursor + 8),
                  let method = data.uint16(at: cursor + 10),
                  let compressedSize = data.uint32(at: cursor + 20),
                  let uncompressedSize = data.uint32(at: cursor + 24),
                  let nameLength = data.uint16(at: cursor + 28),
                  let extraLength = data.uint16(at: cursor + 30),
                  let commentLength = data.uint16(at: cursor + 32),
                  let localOffset = data.uint32(at: cursor + 42) else {
                throw ZIPArchiveError.invalidArchive
            }
            let nameStart = cursor + 46
            let nameEnd = nameStart + Int(nameLength)
            guard nameEnd <= data.count else { throw ZIPArchiveError.invalidArchive }
            let name = String(decoding: data[nameStart..<nameEnd], as: UTF8.self)
            entries[name] = Entry(
                name: name,
                method: method,
                flags: flags,
                compressedSize: Int(compressedSize),
                uncompressedSize: Int(uncompressedSize),
                localHeaderOffset: Int(localOffset)
            )
            cursor = nameEnd + Int(extraLength) + Int(commentLength)
        }
        self.entries = entries
    }

    func contains(_ name: String) -> Bool {
        entries[name] != nil
    }

    func data(for name: String) throws -> Data {
        guard let entry = entries[name] else {
            throw ZIPArchiveError.invalidArchive
        }
        guard entry.flags & 0x1 == 0 else {
            throw ZIPArchiveError.encrypted
        }
        guard entry.uncompressedSize <= maxEntrySize else {
            throw ZIPArchiveError.sizeLimit
        }
        guard data.uint32(at: entry.localHeaderOffset) == 0x0403_4b50,
              let nameLength = data.uint16(at: entry.localHeaderOffset + 26),
              let extraLength = data.uint16(at: entry.localHeaderOffset + 28) else {
            throw ZIPArchiveError.invalidArchive
        }
        let start = entry.localHeaderOffset + 30 + Int(nameLength) + Int(extraLength)
        let end = start + entry.compressedSize
        guard start >= 0, end <= data.count else {
            throw ZIPArchiveError.invalidArchive
        }
        let compressed = data[start..<end]

        switch entry.method {
        case 0:
            return Data(compressed)
        case 8:
            return try inflate(Data(compressed), expectedSize: entry.uncompressedSize)
        default:
            throw ZIPArchiveError.unsupportedCompression
        }
    }

    private func inflate(_ compressed: Data, expectedSize: Int) throws -> Data {
        guard expectedSize > 0 else { return Data() }
        var output = [UInt8](repeating: 0, count: expectedSize)
        let decoded = compressed.withUnsafeBytes { source in
            output.withUnsafeMutableBytes { destination in
                compression_decode_buffer(
                    destination.bindMemory(to: UInt8.self).baseAddress!,
                    expectedSize,
                    source.bindMemory(to: UInt8.self).baseAddress!,
                    compressed.count,
                    nil,
                    COMPRESSION_ZLIB
                )
            }
        }
        guard decoded == expectedSize else {
            throw ZIPArchiveError.invalidArchive
        }
        return Data(output)
    }

    private static func findEndOfCentralDirectory(in data: Data) -> Int? {
        let signature: UInt32 = 0x0605_4b50
        let minimum = 22
        guard data.count >= minimum else { return nil }
        let lowerBound = max(0, data.count - 65_535 - minimum)
        var offset = data.count - minimum
        while offset >= lowerBound {
            if data.uint32(at: offset) == signature {
                return offset
            }
            offset -= 1
        }
        return nil
    }
}

private extension Data {
    func uint16(at offset: Int) -> UInt16? {
        guard offset >= 0, offset + 2 <= count else { return nil }
        return UInt16(self[offset]) | (UInt16(self[offset + 1]) << 8)
    }

    func uint32(at offset: Int) -> UInt32? {
        guard offset >= 0, offset + 4 <= count else { return nil }
        return UInt32(self[offset])
            | (UInt32(self[offset + 1]) << 8)
            | (UInt32(self[offset + 2]) << 16)
            | (UInt32(self[offset + 3]) << 24)
    }
}
