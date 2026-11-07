import XCTest
@testable import flipabulary

final class ImportExportTests: XCTestCase {
    private let legacyAPKG = "UEsDBBQAAAAIAHaAZ11pG9HD7QEAAABAAAAQAAAAY29sbGVjdGlvbi5hbmtpMu3Zv2/TQBQH8Lv8aFWJYlAGDwjl8FIihULSLSw0KKigLtDAAgyX+OKccvZF9gk1ijyY/4KdhQ3xn/A/IDGyMnJ2WpwgRUwIIb4fOX537909x6Pts6en0gg20XHIDTsi1wil5AFjhJDaxe9S9Zc5Jb9XI4fvPu7nm69+Ic4Hp28DAAAAAAAAwB/xqrrrui7NXMNHSox57CfFqfbw2eB4OGDD4/7pgBUpdlv6TEZGBCJm81iGPF6wmVi0WVQW2swvJy1RWXVvFd0jbURSnKob3YvU9u7heveJsn/EiHPTZoYHq2HrOd11Gw2aXV/dhFb2qGzegFbbL+CL8eyyaah9oS7a5s/m1Dkg9gAAAAAAAAD432Uv6A7JDt42ll7H67GlJ30bOm3mRTwUduidzXkkk2mv1+eJHCdeamvdcml3bekw5m+E8tJ0a7Oih2cT+asAm3i5/Fl6FOvI5CUd57vu2ess1/aNZ2Wts1EbnPNwrkRZ7qav07T4Nu+8J85n55MNAAAAAAAAAPCXXJnUyd7+DTaK9UxEN4WdtW5xX+qkGWjtjxaiyYJYCCOjgN3xbfn+3alWvDkVSunmiR22GQ9loA/LdaZ4CcFWz/9fifPd+WYDAAAAAAAAAPy76tmTGqF7k53ssY1UVOrZSZ7wfwBQSwMEFAAAAAgAdoBnXUO/pqMEAAAAAgAAAAUAAABtZWRpYauuBQBQSwECFAMUAAAACAB2gGddaRvRw+0BAAAAQAAAEAAAAAAAAAAAAAAApIEAAAAAY29sbGVjdGlvbi5hbmtpMlBLAQIUAxQAAAAIAHaAZ11Dv6ajBAAAAAIAAAAFAAAAAAAAAAAAAACAARsCAABtZWRpYVBLBQYAAAAAAgACAHEAAABCAgAAAAA="
    private let modernAPKG = "UEsDBBQAAAAAAHaAZ12krlFuCQAAAAkAAAASAAAAY29sbGVjdGlvbi5hbmtpMjFiZmFrZS16c3RkUEsDBBQAAAAAAHaAZ10lncL6BAAAAAQAAAAQAAAAY29sbGVjdGlvbi5hbmtpMnN0dWJQSwECFAMUAAAAAAB2gGddpK5RbgkAAAAJAAAAEgAAAAAAAAAAAAAAgAEAAAAAY29sbGVjdGlvbi5hbmtpMjFiUEsBAhQDFAAAAAAAdoBnXSWdwvoEAAAABAAAABAAAAAAAAAAAAAAAIABOQAAAGNvbGxlY3Rpb24uYW5raTJQSwUGAAAAAAIAAgB+AAAAawAAAAAA"

    func testAnkiLegacyPackageParsesDecksAndFields() throws {
        let data = try XCTUnwrap(Data(base64Encoded: legacyAPKG))
        let plan = try ImportExportService.parseAnki(data: data, fileName: "legacy.apkg")

        XCTAssertEqual(plan.format, .anki)
        XCTAssertEqual(plan.totalCards, 2)
        XCTAssertEqual(plan.skippedRows, 1)
        XCTAssertEqual(plan.decks.map(\.name), ["Spanish · Basics", "Travel"])
        XCTAssertEqual(plan.decks[0].cards[0].word, "hola")
        XCTAssertEqual(plan.decks[0].cards[0].translation, "hello")
        XCTAssertEqual(plan.decks[0].cards[0].example, "Hola, amigo.")
        XCTAssertEqual(plan.decks[0].cards[0].tags, ["greeting", "travel"])
        XCTAssertEqual(plan.decks[1].cards[0].word, "adios")
    }

    func testModernAnkiPackageIsRejected() throws {
        let data = try XCTUnwrap(Data(base64Encoded: modernAPKG))
        XCTAssertThrowsError(try ImportExportService.parseAnki(data: data, fileName: "modern.apkg")) { error in
            XCTAssertEqual(error as? ImportExportError, .modernAnki)
        }
    }

    func testCSVHeadersAndDeckColumn() throws {
        let csv = """
        Word,Translation,Example,Deck
        hola,hello,Hola amigo,Spanish
        adios,goodbye,,Spanish
        perro,dog,,Animals
        """
        let plan = try ImportExportService.parseCSV(data: Data(csv.utf8), fileName: "words.csv")

        XCTAssertEqual(plan.totalCards, 3)
        XCTAssertTrue(plan.usesDeckNames)
        XCTAssertEqual(plan.decks.map(\.name), ["Spanish", "Animals"])
        XCTAssertEqual(plan.decks[0].cards.count, 2)
        XCTAssertEqual(plan.decks[1].cards[0].word, "perro")
    }

    func testCSVWithoutHeaderUsesFirstTwoColumns() throws {
        let csv = "uno,one\n dos, two \n"
        let plan = try ImportExportService.parseCSV(data: Data(csv.utf8), fileName: "basic.txt")

        XCTAssertEqual(plan.totalCards, 2)
        XCTAssertFalse(plan.usesDeckNames)
        XCTAssertEqual(plan.decks[0].name, "basic")
        XCTAssertEqual(plan.decks[0].cards[0].word, "uno")
        XCTAssertEqual(plan.decks[0].cards[1].translation, "two")
    }

    func testCSVHeaderSynonymsAndSemicolonDelimiter() throws {
        let csv = "Front;Back;Example;Pronunciation\nhola;hello;Hola;OH-lah\n"
        let plan = try ImportExportService.parseCSV(data: Data(csv.utf8), fileName: "synonyms.csv")

        XCTAssertEqual(plan.totalCards, 1)
        let card = try XCTUnwrap(plan.decks.first?.cards.first)
        XCTAssertEqual(card.word, "hola")
        XCTAssertEqual(card.translation, "hello")
        XCTAssertEqual(card.example, "Hola")
        XCTAssertEqual(card.phonetic, "OH-lah")
    }

    func testEmptyCSVIsRejected() {
        XCTAssertThrowsError(try ImportExportService.parseCSV(data: Data(), fileName: "empty.csv")) { error in
            XCTAssertEqual(error as? ImportExportError, .invalidCSV)
        }
    }

    func testAnkiHTMLAndClozeAreCleaned() {
        XCTAssertEqual(HTMLText.clean("<b>hola</b><br>amigo"), "hola\namigo")
        XCTAssertEqual(HTMLText.clean("{{c1::hola::hello}}"), "hola")
        XCTAssertEqual(HTMLText.clean("&iquest;C&oacute;mo est&aacute;s?"), "¿Cómo estás?")
    }

    func testCSVQuotedFieldsAndDelimiterDetection() throws {
        let csv = "Word\tTranslation\n\"a,b\"\t\"quote \"\"x\"\"\"\n"
        let table = CSVParser.parse(csv)
        XCTAssertEqual(table.delimiter, .tab)
        XCTAssertEqual(table.rows[1], ["a,b", "quote \"x\""])

        let plan = try ImportExportService.parseCSV(data: Data(csv.utf8), fileName: "quoted.csv")
        XCTAssertEqual(plan.totalCards, 1)
        XCTAssertEqual(plan.decks[0].cards[0].word, "a,b")
        XCTAssertEqual(plan.decks[0].cards[0].translation, "quote \"x\"")
    }

    @MainActor
    func testImportCreatesStacksAndSkipsDuplicates() throws {
        let harness = try TestHarness()
        defer { harness.finish() }

        let plan = ImportPlan(
            format: .anki,
            sourceName: "legacy.apkg",
            decks: [
                ImportedDeck(name: "Spanish", cards: [
                    ImportedCard(word: "hola", translation: "hello", example: nil, translatedExample: nil, phonetic: nil, partOfSpeech: nil, tags: ["greeting"]),
                    ImportedCard(word: "adios", translation: "goodbye", example: nil, translatedExample: nil, phonetic: nil, partOfSpeech: nil, tags: [])
                ])
            ],
            skippedRows: 0,
            usesDeckNames: true
        )

        let first = harness.library.importPlan(plan, destinationStackID: nil)
        guard case .success(let summary) = first else {
            return XCTFail("Expected import success")
        }
        XCTAssertEqual(summary.imported, 2)
        XCTAssertEqual(summary.skipped, 0)
        XCTAssertEqual(summary.stacks, ["Spanish"])

        let stack = try XCTUnwrap(harness.library.stacks().first(where: { $0.name == "Spanish" }))
        XCTAssertEqual(stack.cards.count, 2)
        XCTAssertEqual(stack.cards.first(where: { $0.word == "hola" })?.tags.map(\.name), ["greeting"])

        let second = harness.library.importPlan(plan, destinationStackID: nil)
        guard case .success(let secondSummary) = second else {
            return XCTFail("Expected duplicate import success")
        }
        XCTAssertEqual(secondSummary.imported, 0)
        XCTAssertEqual(secondSummary.skipped, 2)
        XCTAssertEqual(stack.cards.count, 2)
    }

    @MainActor
    func testExportCSVAddsBOMAndQuotesFields() throws {
        let harness = try TestHarness()
        defer { harness.finish() }
        let stack = harness.makeStack(name: "Test")
        let card = harness.makeCard(word: "a,b", translation: "quote \"x\"", stack: stack)
        card.sourceExample = "Hello, world"
        try harness.save()

        let data = ImportExportService.exportCSV(stack: stack)
        XCTAssertEqual(Array(data.prefix(3)), [0xEF, 0xBB, 0xBF])
        let text = try XCTUnwrap(String(data: data.dropFirst(3), encoding: .utf8))
        XCTAssertTrue(text.contains("\"a,b\""))
        XCTAssertTrue(text.contains("\"quote \"\"x\"\"\""))
        XCTAssertTrue(text.contains("\"Hello, world\""))
    }

    @MainActor
    func testAnkiAndPlainTextExports() throws {
        let harness = try TestHarness()
        defer { harness.finish() }
        let stack = harness.makeStack(name: "Export")
        harness.makeCard(word: "hola", translation: "hello", stack: stack)
        harness.makeCard(word: "adios", translation: "goodbye", stack: stack)
        try harness.save()

        let anki = try XCTUnwrap(String(data: ImportExportService.exportAnkiText(stack: stack), encoding: .utf8))
        XCTAssertTrue(anki.contains("#separator:tab"))
        XCTAssertTrue(anki.contains("#tags column:3"))
        XCTAssertTrue(anki.contains("hola\thello"))

        let plain = try XCTUnwrap(String(data: ImportExportService.exportPlainText(stack: stack), encoding: .utf8))
        XCTAssertEqual(plain.split(separator: "\n").count, 2)
        XCTAssertTrue(plain.contains("adios\tgoodbye"))
    }

    @MainActor
    func testCSVImportIntoSelectedStack() throws {
        let harness = try TestHarness()
        defer { harness.finish() }
        let target = harness.makeStack(name: "Target")
        let plan = ImportPlan(
            format: .csv,
            sourceName: "words.csv",
            decks: [
                ImportedDeck(name: "words", cards: [
                    ImportedCard(word: "uno", translation: "one", example: nil, translatedExample: nil, phonetic: nil, partOfSpeech: nil, tags: [])
                ])
            ],
            skippedRows: 0,
            usesDeckNames: false
        )

        let result = harness.library.importPlan(plan, destinationStackID: target.id)
        guard case .success = result else { return XCTFail("Expected import success") }
        XCTAssertEqual(target.cards.count, 1)
        XCTAssertEqual(target.cards.first?.word, "uno")
    }
}
