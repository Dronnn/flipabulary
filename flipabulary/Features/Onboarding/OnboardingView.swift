import SwiftUI
import WidgetKit

struct OnboardingView: View {
    @Environment(AppEnvironment.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var setDemo = OnboardingSetOrderDemo()
    @State private var learningDemo = OnboardingLearningDemo()
    @State private var demoShowingBack = false
    @State private var demoDragOffset: CGSize = .zero
    @State private var demoIsThrowing = false
    @State private var selectedWidgetSetID: UUID?

    private var selectedLanguage: AppLanguage {
        app.preferences.preferences.language ?? .system
    }

    var body: some View {
        @Bindable var store = app.onboarding

        ZStack {
            AppColor.page.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar(store: store)

                TabView(selection: stepBinding(store)) {
                    ForEach(OnboardingStep.allCases, id: \.rawValue) { step in
                        page(for: step)
                            .tag(step)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                footer(store: store)
            }
        }
        .interactiveDismissDisabled()
    }

    // MARK: - Chrome

    private func topBar(store: OnboardingStore) -> some View {
        HStack {
            Text(verbatim: "Flipabulary")
                .font(AppFont.font(15, .semibold))
                .foregroundStyle(AppColor.textPrimary)

            Spacer()

            Button {
                app.haptics.selection()
                store.skip()
            } label: {
                Text("Skip")
                    .font(AppFont.font(14, .semibold))
                    .foregroundStyle(AppColor.accentStrong)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("onboarding.skip")
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)
    }

    private func footer(store: OnboardingStore) -> some View {
        VStack(spacing: 14) {
            HStack(spacing: 6) {
                ForEach(OnboardingStep.allCases, id: \.rawValue) { step in
                    Capsule()
                        .fill(step.rawValue <= store.step.rawValue ? AppColor.accent : AppColor.divider)
                        .frame(width: step == store.step ? 20 : 6, height: 6)
                }
            }
            .accessibilityHidden(true)

            PrimaryActionButton(
                title: store.isLastStep ? "Get started" : "Next",
                systemImage: store.isLastStep ? "checkmark" : nil
            ) {
                app.haptics.selection()
                if store.isLastStep {
                    store.complete()
                } else {
                    withAnimation(animation) {
                        store.advance()
                    }
                }
            }
            .accessibilityIdentifier("onboarding.next")
            .accessibilityHint("Step \(store.stepNumber) of \(store.stepCount)")
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }

    private func stepBinding(_ store: OnboardingStore) -> Binding<OnboardingStep> {
        Binding(
            get: { store.step },
            set: { newValue in
                if newValue != store.step {
                    store.select(newValue)
                }
            }
        )
    }

    // MARK: - Pages

    private func page(for step: OnboardingStep) -> some View {
        ScrollView {
            VStack(spacing: 24) {
                hero(for: step)
                textBlock(for: step)
            }
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 16)
        }
        .scrollIndicators(.hidden)
    }

    @ViewBuilder
    private func hero(for step: OnboardingStep) -> some View {
        switch step {
        case .welcome:
            heroCard {
                VStack(spacing: 14) {
                    OnboardingWidgetPreview(
                        entry: sampleWidgetEntry(setID: Self.welcomeSetID, name: "Spanish B1", rows: Self.welcomeRows),
                        family: .systemMedium
                    )
                    .allowsHitTesting(false)
                    languageMenu
                }
            }
        case .wordSets:
            heroCard {
                setPreviewList
            }
        case .learning:
            heroCard {
                VStack(spacing: 12) {
                    interactiveReviewCard
                    demoActions
                }
            }
        case .widgets:
            heroCard {
                VStack(spacing: 10) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            widgetButton(
                                entry: sampleWidgetEntry(setID: Self.travelSetID, name: "Travel", rows: Self.travelRows),
                                setID: Self.travelSetID,
                                name: "Travel"
                            )
                            widgetButton(
                                entry: sampleWidgetEntry(setID: Self.spanishSetID, name: "Spanish B1", rows: Self.spanishRows),
                                setID: Self.spanishSetID,
                                name: "Spanish B1"
                            )
                        }
                        .padding(.vertical, 4)
                    }

                    HStack(spacing: 6) {
                        Image(systemName: "hand.tap")
                        Text("Tap a widget to see its set")
                    }
                    .font(AppFont.font(13, .semibold))
                    .foregroundStyle(AppColor.textPrimary)
                }
            }
        case .ready:
            heroCard {
                ZStack {
                    Circle()
                        .fill(AppColor.surface)
                        .frame(width: 120, height: 120)
                        .shadow(color: AppColor.shadow.opacity(0.08), radius: 12, y: 6)
                    Image(systemName: "checkmark")
                        .font(.system(size: 44, weight: .semibold))
                        .foregroundStyle(AppColor.accentStrong)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
                .accessibilityHidden(true)
            }
        }
    }

    @ViewBuilder
    private func textBlock(for step: OnboardingStep) -> some View {
        switch step {
        case .welcome:
            textBlock(eyebrow: "Welcome", title: "Welcome to Flipabulary", body: "Save words, build sets for your widgets, and remember them with short reviews.")
        case .wordSets:
            textBlock(eyebrow: "Word sets", title: "A set for every widget", body: "A word set is your own list of words. Each widget can show a different set, and you decide the order.")
        case .learning:
            textBlock(eyebrow: "How it works", title: "Learn, then keep it", body: "See the answer, then rate yourself. By default, five Good answers in a row make a word Learned.")
            pageBody("Learned words return at 1 day, 3 days, 7 days, 2 weeks, and 1 month. Skip those reviews and a word loses progress; eventually it returns to Learning.")
        case .widgets:
            VStack(spacing: 10) {
                textBlock(eyebrow: "Widgets", title: "Your words on the Home Screen", body: "Add a Flipabulary widget, then choose its word set in Edit Widget. Add another widget and choose a different set.")
                VStack(alignment: .leading, spacing: 8) {
                    onboardingSectionHeader("How to add a widget")
                    GroupedSurface {
                        instructionRow(1, "Touch and hold an empty area of the Home Screen.")
                        SettingsDivider(inset: 50)
                        instructionRow(2, "Tap Edit or Add Widget, search for Flipabulary, and choose Word list.")
                    }
                }
                .padding(.top, 6)
            }
        case .ready:
            textBlock(eyebrow: "Get started", title: "You're ready", body: "Add your first word or import a deck from Words. You can build sets and widgets whenever you like.")
        }
    }

    private func textBlock(eyebrow: String, title: String, body: String) -> some View {
        VStack(spacing: 10) {
            onboardingEyebrow(eyebrow)
            pageTitle(title)
            pageBody(body)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
    }

    private func heroCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(16)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .fill(AppColor.accentSoft)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .stroke(AppColor.divider, lineWidth: 1)
            )
            .shadow(color: AppColor.shadow.opacity(0.10), radius: 24, y: 12)
    }

    // MARK: - Word set hero

    private var setPreviewList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Words")
                .font(AppFont.font(13, .regular))
                .foregroundStyle(AppColor.textPrimary)

            List {
                ForEach(Array(setDemo.words.enumerated()), id: \.element) { index, word in
                    WidgetWordSetRowView(row: sampleSetRow(for: word))
                        .accessibilityIdentifier("onboarding.set.row.\(index)")
                }
                .onMove { offsets, destination in
                    withAnimation(animation) {
                        setDemo.move(fromOffsets: offsets, toOffset: destination)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .scrollDisabled(true)
            .environment(\.editMode, .constant(.active))
            .contentMargins(.top, 0, for: .scrollContent)
            .frame(height: 255)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "hand.draw")
                Text("Drag words to reorder. Each widget can use a different set.")
            }
            .font(AppFont.caption())
            .foregroundStyle(AppColor.accentStrong)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(AppColor.page)
        )
    }

    // MARK: - Learning hero

    @ViewBuilder
    private var interactiveReviewCard: some View {
        if demoShowingBack && !learningDemo.isLearned {
            reviewCard.highPriorityGesture(demoCardDragGesture)
        } else {
            reviewCard
        }
    }

    private var reviewCard: some View {
        OnboardingReviewCardView(
            word: wordDemo,
            translation: translationDemo,
            sourceExample: "Smartphones are ubiquitous today.",
            translatedExample: nil,
            phonetic: nil,
            partOfSpeech: nil,
            stateTitle: demoStateTitle,
            repeatCount: learningDemo.repeatCount,
            threshold: learningDemo.threshold,
            showingBack: demoShowingBack,
            translationFirst: false,
            expanded: false,
            compact: true,
            showsBackHint: false
        )
        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .onTapGesture {
            if learningDemo.isRevealed {
                withAnimation(animation) {
                    demoShowingBack.toggle()
                }
            } else {
                revealDemo()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(demoShowingBack ? "\(translationDemo), \(wordDemo)" : wordDemo)
        .accessibilityHint(demoShowingBack ? "Double tap to flip back." : "Double tap to show the answer.")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("onboarding.demo.card")
        .offset(demoDragOffset)
        .rotationEffect(.degrees(max(-12, min(12, Double(demoDragOffset.width / 22)))))
        .scaleEffect(1 - min(abs(demoDragOffset.width) / 4_000, 0.04))
        .overlay(alignment: .topLeading) {
            demoStamp(
                text: "AGAIN",
                color: AppColor.danger,
                opacity: demoDragOffset.width < 0 ? demoDragProgress : 0,
                rotation: -11
            )
        }
        .overlay(alignment: .topTrailing) {
            demoStamp(
                text: "GOOD",
                color: AppColor.success,
                opacity: demoDragOffset.width > 0 ? demoDragProgress : 0,
                rotation: 11
            )
        }
    }

    private var demoDragProgress: Double {
        min(1, abs(demoDragOffset.width) / demoThrowThreshold)
    }

    private let demoThrowThreshold: CGFloat = 70

    private var demoCardDragGesture: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                guard demoShowingBack, !learningDemo.isLearned, !demoIsThrowing else { return }
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                demoDragOffset = CGSize(
                    width: value.translation.width,
                    height: value.translation.height * 0.25
                )
            }
            .onEnded { value in
                guard demoShowingBack, !learningDemo.isLearned, !demoIsThrowing else {
                    demoDragOffset = .zero
                    return
                }
                let actual = value.translation.width
                let predicted = value.predictedEndTranslation.width
                let horizontal = abs(predicted) > abs(actual) ? predicted : actual
                guard abs(horizontal) >= demoThrowThreshold,
                      abs(horizontal) > abs(value.translation.height) else {
                    withAnimation(animation) {
                        demoDragOffset = .zero
                    }
                    return
                }
                throwDemo(grade: horizontal > 0 ? .good : .again)
            }
    }

    private func throwDemo(grade: ReviewGrade) {
        guard !demoIsThrowing else { return }
        demoIsThrowing = true
        let direction: CGFloat = grade == .good ? 1 : -1
        withAnimation(.easeOut(duration: 0.28)) {
            demoDragOffset = CGSize(width: direction * 900, height: demoDragOffset.height)
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(260))
            learningDemo.rate(grade)
            demoDragOffset = .zero
            demoIsThrowing = false
        }
    }

    private func demoStamp(text: String, color: Color, opacity: Double, rotation: Double) -> some View {
        Text(LocalizedStringKey(text))
            .font(AppFont.font(19, .bold))
            .tracking(1.4)
            .foregroundStyle(color)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(color, lineWidth: 3)
            )
            .rotationEffect(.degrees(rotation))
            .opacity(opacity)
            .padding(22)
            .allowsHitTesting(false)
    }

    private var demoActions: some View {
        VStack(spacing: 8) {
            if learningDemo.isLearned {
                Text("Learned. It will come back tomorrow.")
                    .font(AppFont.body())
                    .foregroundStyle(AppColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                TextLinkButton(title: "Try again") {
                    resetDemo()
                }
                .accessibilityIdentifier("onboarding.demo.reset")
            } else if !learningDemo.isRevealed {
                PrimaryActionButton(title: "Show answer", systemImage: "eye") {
                    revealDemo()
                }
                .accessibilityIdentifier("onboarding.demo.reveal")
            } else if demoShowingBack {
                HStack(spacing: 16) {
                    demoRatingButton(title: "Again", subtitle: "reset", grade: .again, filled: false)
                        .accessibilityIdentifier("onboarding.demo.again")
                    demoRatingButton(title: "Good", subtitle: "remembered", grade: .good, filled: true)
                        .accessibilityIdentifier("onboarding.demo.good")
                }

                if let grade = learningDemo.lastGrade {
                    Text(feedbackText(for: grade))
                        .font(AppFont.body())
                        .foregroundStyle(AppColor.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func widgetButton(entry: FlipWidgetEntry, setID: UUID, name: String) -> some View {
        Button {
            app.haptics.selection()
            selectedWidgetSetID = setID
        } label: {
            OnboardingWidgetPreview(
                entry: entry,
                family: .systemSmall,
                width: 155,
                height: 155,
                isSelected: selectedWidgetSetID == setID
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(name) widget")
        .accessibilityIdentifier("onboarding.widget.\(name)")
    }

    private func demoRatingButton(title: String, subtitle: String, grade: ReviewGrade, filled: Bool) -> some View {
        Button {
            app.haptics.impact(grade == .good ? .medium : .rigid)
            withAnimation(animation) {
                learningDemo.rate(grade)
            }
        } label: {
            VStack(spacing: 2) {
                Text(LocalizedStringKey(title))
                    .font(AppFont.primaryAction())
                Text(LocalizedStringKey(subtitle))
                    .font(AppFont.font(10, .regular))
                    .opacity(filled ? 1 : 0.8)
            }
            .foregroundStyle(filled ? AppColor.onAccent : AppColor.danger)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(filled ? AppColor.accentStrong : AppColor.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(filled ? .clear : AppColor.divider, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Copy and shared pieces

    private var wordDemo: String { "ubiquitous" }
    private var translationDemo: String { "ubicuo" }

    private var demoStateTitle: String {
        if learningDemo.isLearned { return "LEARNED" }
        if learningDemo.repeatCount > 0 { return "LEARNING" }
        return "NEW CARD"
    }

    private func feedbackText(for grade: ReviewGrade) -> LocalizedStringKey {
        switch grade {
        case .good:
            "Good. \(learningDemo.repeatCount) of \(learningDemo.threshold) repeats."
        case .again:
            "Again. The streak starts over."
        }
    }

    private func revealDemo() {
        app.haptics.impact()
        withAnimation(animation) {
            learningDemo.reveal()
            demoShowingBack = true
            demoDragOffset = .zero
        }
    }

    private func resetDemo() {
        app.haptics.selection()
        withAnimation(animation) {
            learningDemo.tryAgain()
            demoShowingBack = false
            demoDragOffset = .zero
        }
    }

    private func onboardingEyebrow(_ title: String) -> some View {
        Text(LocalizedStringKey(title))
            .font(AppFont.font(13, .semibold))
            .foregroundStyle(AppColor.textPrimary)
            .accessibilityAddTraits(.isHeader)
    }

    private func onboardingSectionHeader(_ title: String) -> some View {
        Text(LocalizedStringKey(title))
            .font(AppFont.font(13, .semibold))
            .foregroundStyle(AppColor.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }

    private func pageTitle(_ title: String) -> some View {
        Text(LocalizedStringKey(title))
            .font(AppFont.screenTitle())
            .foregroundStyle(AppColor.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }

    private func pageBody(_ text: String) -> some View {
        Text(LocalizedStringKey(text))
            .font(AppFont.body())
            .foregroundStyle(AppColor.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var languageMenu: some View {
        Menu {
            ForEach(AppLanguage.allCases) { language in
                Button {
                    app.preferences.preferences.language = language
                    app.haptics.selection()
                    app.maintenance.publishSnapshot()
                } label: {
                    if language == selectedLanguage {
                        Label {
                            languageLabel(language)
                        } icon: {
                            Image(systemName: "checkmark")
                        }
                    } else {
                        languageLabel(language)
                    }
                }
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "globe")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AppColor.accentStrong)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Choose language")
                        .font(AppFont.fieldValue())
                        .foregroundStyle(AppColor.textPrimary)
                    Text("Tap to choose now. You can change it later in Settings.")
                        .font(AppFont.caption())
                        .foregroundStyle(AppColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                Text(verbatim: selectedLanguage.isSystem ? app.localized("System") : selectedLanguage.nativeName)
                    .font(AppFont.font(14, .semibold))
                    .foregroundStyle(AppColor.accentStrong)

                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(AppColor.onAccent)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(AppColor.accentStrong))
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: AppMetrics.cardRadius, style: .continuous)
                    .fill(AppColor.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppMetrics.cardRadius, style: .continuous)
                    .stroke(AppColor.accentStrong.opacity(0.45), lineWidth: 1.5)
            )
        }
        .accessibilityIdentifier("onboarding.language")
    }

    @ViewBuilder
    private func languageLabel(_ language: AppLanguage) -> some View {
        if language.isSystem {
            Text("System")
        } else {
            Text(verbatim: language.nativeName)
        }
    }

    private func instructionRow(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(AppFont.font(12, .bold))
                .foregroundStyle(AppColor.onAccent)
                .frame(width: 24, height: 24)
                .background(Circle().fill(AppColor.accentStrong))

            Text(LocalizedStringKey(text))
                .font(AppFont.body())
                .foregroundStyle(AppColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var animation: Animation? {
        reduceMotion ? nil : .easeInOut(duration: 0.22)
    }

    // MARK: - Sample data

    private func sampleSetRow(for word: String) -> WidgetWordSetDisplayRow {
        let sample: (translation: String, stack: String, id: UUID)
        switch word {
        case "resilient":
            sample = ("resiliente", "Spanish B1", Self.resilientCardID)
        case "mitigate":
            sample = ("mitigar", "Spanish B1", Self.mitigateCardID)
        default:
            sample = ("ubicuo", "Spanish B1", Self.ubiquitousCardID)
        }
        return WidgetWordSetDisplayRow(
            id: sample.id,
            word: word,
            translation: sample.translation,
            stackName: sample.stack
        )
    }

    private func sampleWidgetEntry(
        setID: UUID,
        name: String,
        rows: [(word: String, translation: String, repeats: Int)]
    ) -> FlipWidgetEntry {
        let now = Date()
        let cards = rows.enumerated().map { index, row in
            WidgetCardSnapshot(
                id: Self.cardID(setIndex: setID, rowIndex: index),
                word: row.word,
                translation: row.translation,
                lifecycle: "learning",
                repeatCount: row.repeats,
                threshold: 5,
                dueAt: now,
                createdAt: now.addingTimeInterval(TimeInterval(index))
            )
        }
        let set = WidgetWordSetSnapshot(
            id: setID,
            name: name,
            cards: cards,
            savedCount: cards.count,
            dueCount: cards.count,
            learnedCount: 0,
            learningCount: cards.count,
            newCount: 0,
            nextDueAt: now
        )
        let snapshot = WidgetSnapshot(
            schemaVersion: WidgetSnapshot.currentSchemaVersion,
            generatedAt: now,
            stacks: [],
            defaultStackID: nil,
            defaultSort: .dueFirst,
            defaultShowTranslations: true,
            wordSets: [set],
            defaultWordSetID: set.id
        )
        return FlipWidgetEntry(
            date: now,
            snapshot: snapshot,
            stackID: nil,
            wordSetID: set.id,
            sort: .manual,
            showTranslations: true,
            missingConfiguredStack: false,
            missingConfiguredWordSet: false,
            isPlaceholder: false
        )
    }

    private static func cardID(setIndex: UUID, rowIndex: Int) -> UUID {
        let seed = setIndex.uuidString.replacingOccurrences(of: "-", with: "")
        let prefix = String(seed.prefix(20))
        let suffix = String(format: "%012d", rowIndex + 1)
        return UUID(uuidString: "\(prefix.prefix(8))-\(prefix.dropFirst(8).prefix(4))-\(prefix.dropFirst(12).prefix(4))-\(prefix.dropFirst(16).prefix(4))-\(suffix)") ?? UUID()
    }

    private static let welcomeSetID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    private static let travelSetID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
    private static let spanishSetID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
    private static let ubiquitousCardID = UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000001")!
    private static let resilientCardID = UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000002")!
    private static let mitigateCardID = UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000003")!

    private static let welcomeRows: [(word: String, translation: String, repeats: Int)] = [
        ("ubiquitous", "ubicuo", 2),
        ("resilient", "resiliente", 4),
        ("mitigate", "mitigar", 1),
        ("ambiguous", "ambiguo", 3)
    ]

    private static let travelRows: [(word: String, translation: String, repeats: Int)] = [
        ("ephemeral", "efímero", 3),
        ("ambiguous", "ambiguo", 4),
        ("resilient", "resiliente", 1)
    ]

    private static let spanishRows: [(word: String, translation: String, repeats: Int)] = [
        ("ubiquitous", "ubicuo", 2),
        ("mitigate", "mitigar", 1),
        ("resilient", "resiliente", 5)
    ]
}

private struct OnboardingWidgetPreview: View {
    let entry: FlipWidgetEntry
    let family: WidgetFamily
    var width: CGFloat?
    var height: CGFloat = 170
    var isSelected: Bool = false

    var body: some View {
        ListWidgetView(entry: entry, familyOverride: family)
            .frame(width: width, height: height)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(AppColor.surface)
            )
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(isSelected ? AppColor.accentStrong : AppColor.divider, lineWidth: isSelected ? 2.5 : 1)
            )
            .shadow(color: AppColor.shadow.opacity(0.08), radius: 14, y: 8)
            .accessibilityHidden(true)
    }
}
