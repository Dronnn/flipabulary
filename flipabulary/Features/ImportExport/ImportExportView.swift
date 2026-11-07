import SwiftUI
import UniformTypeIdentifiers

struct ImportExportView: View {
    @Environment(AppEnvironment.self) private var app

    @State private var selectedStackID: UUID?
    @State private var isCSVImporterPresented = false
    @State private var isAnkiImporterPresented = false
    @State private var pendingPlan: ImportPlan?
    @State private var errorMessage: String?
    @State private var isLoadingFile = false

    @State private var exportDocument: ExportFileDocument?
    @State private var exportContentType: UTType = .commaSeparatedText
    @State private var exportFileName = "Flipabulary"
    @State private var isExporterPresented = false

    private var stacks: [VocabularyStack] { app.library.stacks() }

    private var selectedStack: VocabularyStack? {
        if let selectedStackID, let stack = app.library.stack(id: selectedStackID) {
            return stack
        }
        return app.library.defaultStack() ?? stacks.first
    }

    private let textTypes: [UTType] = [.commaSeparatedText, .tabSeparatedText, .plainText, .text]
    private let ankiTypes: [UTType] = {
        var types: [UTType] = [.zip, .data]
        if let apkg = UTType(filenameExtension: "apkg") { types.insert(apkg, at: 0) }
        if let colpkg = UTType(filenameExtension: "colpkg") { types.insert(colpkg, at: 0) }
        return types
    }()

    var body: some View {
        GeometryReader { proxy in
            let mode = AppMetrics.LayoutMode.resolve(width: proxy.size.width)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    intro
                    importSection
                    supportedFormats
                    exportSection
                    notes
                    if let errorMessage {
                        InlineMessage(text: errorMessage)
                    }
                }
                .frame(maxWidth: 820)
                .padding(.horizontal, mode.inset)
                .padding(.top, 12)
                .padding(.bottom, 28)
            }
            .pageBackground()
            .navigationTitle("Import & Export")
            .navigationBarTitleDisplayMode(.large)
            .overlay {
                if isLoadingFile {
                    ProgressView()
                        .padding(20)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }
        }
        .fileImporter(
            isPresented: $isCSVImporterPresented,
            allowedContentTypes: textTypes,
            allowsMultipleSelection: false
        ) { result in
            handleImport(result, format: .csv)
        }
        .fileImporter(
            isPresented: $isAnkiImporterPresented,
            allowedContentTypes: ankiTypes,
            allowsMultipleSelection: false
        ) { result in
            handleImport(result, format: .anki)
        }
        .sheet(item: $pendingPlan) { plan in
            ImportPreviewView(plan: plan) { summary in
                report(summary)
            }
            .environment(app)
        }
        .fileExporter(
            isPresented: $isExporterPresented,
            document: exportDocument,
            contentType: exportContentType,
            defaultFilename: exportFileName
        ) { result in
            switch result {
            case .success:
                app.router.showToast(app.localized("Exported."))
            case .failure:
                errorMessage = app.localized("Export failed.")
            }
        }
    }

    private var intro: some View {
        Text("Bring your words from another app. Files are processed on this device.")
            .font(AppFont.body())
            .foregroundStyle(AppColor.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var importSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Import")
            GroupedSurface {
                actionRow(
                    title: "CSV or text file",
                    subtitle: "Import words from a spreadsheet or text export.",
                    systemImage: "tablecells"
                ) {
                    isCSVImporterPresented = true
                }
                .accessibilityIdentifier("import.csv")
                SettingsDivider(inset: 16)
                actionRow(
                    title: "Anki deck (.apkg)",
                    subtitle: "Import decks exported from Anki.",
                    systemImage: "rectangle.stack"
                ) {
                    isAnkiImporterPresented = true
                }
                .accessibilityIdentifier("import.anki")
            }
        }
    }

    private var supportedFormats: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Supported import formats")
            GroupedSurface {
                formatInfo(
                    title: "CSV, TSV, and TXT",
                    description: "One row per card. Headers can be Word, Translation, Example, Translated example, Phonetic, Part of speech, and Tags. Without headers, the first two columns are used as word and translation."
                )
                SettingsDivider(inset: 16)
                formatInfo(
                    title: "Anki .apkg",
                    description: "Legacy .apkg files with collection.anki2 or collection.anki21. Each Anki deck becomes a stack. In Anki, export with Support older Anki versions enabled."
                )
                SettingsDivider(inset: 16)
                formatInfo(
                    title: "Modern Anki files",
                    description: "If the file contains collection.anki21b, re-export it from Anki with Support older Anki versions enabled."
                )
            }
        }
    }

    private var exportSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Export")
            Text("Choose one stack. The export includes word, translation, examples, phonetic, part of speech, and tags where available.")
                .font(AppFont.caption())
                .foregroundStyle(AppColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            GroupedSurface {
                Menu {
                    ForEach(stacks) { stack in
                        Button(stack.name) { selectedStackID = stack.id }
                    }
                } label: {
                    HStack {
                        Text("Stack")
                            .font(AppFont.fieldValue())
                            .foregroundStyle(AppColor.textPrimary)
                        Spacer()
                        Text(selectedStack?.name ?? "Choose stack")
                            .font(AppFont.font(14, .regular))
                            .foregroundStyle(AppColor.textSecondary)
                            .lineLimit(1)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(AppColor.textMuted)
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 52)
                    .contentShape(Rectangle())
                }
                .accessibilityIdentifier("export.stack")

                SettingsDivider(inset: 16)
                exportRow("Export CSV", subtitle: "Opens in any spreadsheet.", systemImage: "tablecells") {
                    export(.csv)
                }
                SettingsDivider(inset: 16)
                exportRow("Anki text (.txt)", subtitle: "Import into Anki with File > Import.", systemImage: "rectangle.stack") {
                    export(.anki)
                }
                SettingsDivider(inset: 16)
                exportRow("Quizlet / Memrise (.txt)", subtitle: "Plain tab-separated word and translation.", systemImage: "text.alignleft") {
                    export(.plain)
                }
            }
        }
    }

    private var notes: some View {
        VStack(alignment: .leading, spacing: 8) {
            InlineMessage(
                text: app.localized("All imported cards start as New. Media and review history are not imported."),
                kind: .info
            )
            InlineMessage(
                text: app.localized("Files are processed on this device and are not uploaded."),
                kind: .info
            )
        }
    }

    private func actionRow(
        title: String,
        subtitle: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(AppColor.accentStrong)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(LocalizedStringKey(title))
                        .font(AppFont.fieldValue())
                        .foregroundStyle(AppColor.textPrimary)
                    Text(LocalizedStringKey(subtitle))
                        .font(AppFont.caption())
                        .foregroundStyle(AppColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppColor.textMuted)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(minHeight: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func exportRow(
        _ title: String,
        subtitle: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        actionRow(title: title, subtitle: subtitle, systemImage: systemImage, action: action)
    }

    private func formatInfo(title: String, description: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(LocalizedStringKey(title))
                .font(AppFont.fieldValue())
                .foregroundStyle(AppColor.textPrimary)
            Text(LocalizedStringKey(description))
                .font(AppFont.caption())
                .foregroundStyle(AppColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
    }

    private func handleImport(_ result: Result<[URL], Error>, format: ImportFormat) {
        errorMessage = nil
        switch result {
        case .failure:
            errorMessage = app.localized("The file could not be read.")
        case .success(let urls):
            guard let url = urls.first else { return }
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            isLoadingFile = true
            do {
                let data = try Data(contentsOf: url)
                let plan: ImportPlan
                switch format {
                case .csv:
                    plan = try ImportExportService.parseCSV(data: data, fileName: url.lastPathComponent)
                case .anki:
                    plan = try ImportExportService.parseAnki(data: data, fileName: url.lastPathComponent)
                }
                pendingPlan = plan
            } catch {
                errorMessage = errorMessage(for: error)
            }
            isLoadingFile = false
        }
    }

    private func errorMessage(for error: Error) -> String {
        guard let error = error as? ImportExportError else {
            return app.localized("Import failed.")
        }
        switch error {
        case .unreadableFile:
            return app.localized("The file could not be read.")
        case .invalidCSV, .noValidRows:
            return app.localized("No valid cards were found. Check the file and column layout.")
        case .modernAnki:
            return app.localized("This Anki file uses the modern compressed format. Re-export it with Support older Anki versions enabled.")
        case .invalidAnki, .unsupportedArchive:
            return app.localized("This file is not a supported Anki package.")
        case .emptyStack:
            return app.localized("Choose a stack to export.")
        }
    }

    private func report(_ summary: ImportSummary) {
        let message = String(
            format: app.localized("Imported %lld words."),
            summary.imported
        )
        app.router.showToast(message)
    }

    private enum ExportFormat {
        case csv
        case anki
        case plain
    }

    private func export(_ format: ExportFormat) {
        guard let stack = selectedStack else {
            errorMessage = app.localized("Choose a stack to export.")
            return
        }
        errorMessage = nil
        let data: Data
        let contentType: UTType
        switch format {
        case .csv:
            data = ImportExportService.exportCSV(stack: stack)
            contentType = .commaSeparatedText
        case .anki:
            data = ImportExportService.exportAnkiText(stack: stack)
            contentType = .plainText
        case .plain:
            data = ImportExportService.exportPlainText(stack: stack)
            contentType = .plainText
        }
        exportDocument = ExportFileDocument(data: data)
        exportContentType = contentType
        exportFileName = safeFileName(stack.name)
        isExporterPresented = true
    }

    private func safeFileName(_ name: String) -> String {
        let cleaned = name
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "\\", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Flipabulary" : String(cleaned.prefix(60))
    }
}

struct ImportPreviewView: View {
    @Environment(AppEnvironment.self) private var app
    @Environment(\.dismiss) private var dismiss

    let plan: ImportPlan
    let onImported: (ImportSummary) -> Void

    @State private var destinationStackID: UUID?
    @State private var isImporting = false
    @State private var errorMessage: String?

    private var stacks: [VocabularyStack] { app.library.stacks() }

    private var destinationName: String {
        if plan.usesDeckNames {
            return app.localized("Each deck becomes its own stack.")
        }
        if let destinationStackID, let stack = app.library.stack(id: destinationStackID) {
            return stack.name
        }
        return plan.suggestedStackName
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    summary
                    if plan.usesDeckNames {
                        Text(LocalizedStringKey("Each deck becomes its own stack."))
                            .font(AppFont.body())
                            .foregroundStyle(AppColor.textSecondary)
                    } else {
                        destinationPicker
                    }
                    preview
                    if plan.skippedRows > 0 {
                        InlineMessage(
                            text: String(
                                format: app.localized("%lld rows were skipped."),
                                plan.skippedRows
                            ),
                            kind: .info
                        )
                    }
                    if let errorMessage {
                        InlineMessage(text: errorMessage)
                    }
                }
                .padding(20)
            }
            .pageBackground()
            .navigationTitle("Preview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import") { importPlan() }
                        .disabled(plan.totalCards == 0 || isImporting)
                }
            }
        }
    }

    private var summary: some View {
        GroupedSurface {
            VStack(alignment: .leading, spacing: 8) {
                Text(plan.sourceName)
                    .font(AppFont.fieldValue())
                    .foregroundStyle(AppColor.textPrimary)
                    .lineLimit(2)
                HStack(spacing: 12) {
                    Label(String(format: app.localized("%lld words"), plan.totalCards), systemImage: "textformat")
                    Label(String(format: app.localized("%lld stacks"), plan.decks.count), systemImage: "square.stack.3d.up")
                }
                .font(AppFont.caption())
                .foregroundStyle(AppColor.textSecondary)
            }
            .padding(16)
        }
    }

    private var destinationPicker: some View {
        GroupedSurface {
            Menu {
                Button {
                    destinationStackID = nil
                } label: {
                    Text(String(format: app.localized("New stack: %@"), plan.suggestedStackName))
                }
                ForEach(stacks) { stack in
                    Button(stack.name) { destinationStackID = stack.id }
                }
            } label: {
                HStack {
                    Text("Import into")
                        .font(AppFont.fieldValue())
                        .foregroundStyle(AppColor.textPrimary)
                    Spacer()
                    Text(destinationName)
                        .font(AppFont.font(14, .regular))
                        .foregroundStyle(AppColor.textSecondary)
                        .lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AppColor.textMuted)
                }
                .padding(.horizontal, 16)
                .frame(height: 52)
                .contentShape(Rectangle())
            }
        }
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Preview")
            ForEach(Array(plan.decks.prefix(3).enumerated()), id: \.offset) { _, deck in
                GroupedSurface {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(deck.name)
                                .font(AppFont.fieldValue())
                                .foregroundStyle(AppColor.textPrimary)
                                .lineLimit(1)
                            Spacer()
                            Text("\(deck.cards.count) words")
                                .font(AppFont.caption())
                                .foregroundStyle(AppColor.textSecondary)
                        }
                        ForEach(Array(deck.cards.prefix(3).enumerated()), id: \.offset) { _, card in
                            HStack(alignment: .top, spacing: 8) {
                                Text(card.word)
                                    .font(AppFont.font(13, .semibold))
                                    .foregroundStyle(AppColor.textPrimary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Text(card.translation)
                                    .font(AppFont.font(13, .regular))
                                    .foregroundStyle(AppColor.textSecondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                    .padding(16)
                }
            }
        }
    }

    private func importPlan() {
        guard !isImporting else { return }
        isImporting = true
        errorMessage = nil
        let result = app.library.importPlan(
            plan,
            destinationStackID: plan.usesDeckNames ? nil : destinationStackID
        )
        switch result {
        case .success(let summary):
            onImported(summary)
            dismiss()
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
        isImporting = false
    }
}

struct ExportFileDocument: FileDocument {
    static var readableContentTypes: [UTType] {
        [.commaSeparatedText, .tabSeparatedText, .plainText, .text]
    }

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
