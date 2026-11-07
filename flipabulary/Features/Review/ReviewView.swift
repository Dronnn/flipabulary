import SwiftUI
import SwiftData
import UIKit

struct ReviewView: View {
    @Environment(AppEnvironment.self) private var app
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let sessionID: UUID
    let onClose: () -> Void

    @State private var session: ReviewSession?
    @State private var card: VocabularyCard?
    @State private var loadError: String?
    @State private var showEndConfirmation = false
    @State private var showSettings = false
    @State private var ratingLocked = false
    @State private var now = Date()
    @State private var reviewStarted = false
    @State private var dragOffset: CGSize = .zero
    @State private var isThrowing = false
    @State private var didCrossSwipeThreshold = false

    private let swipeThreshold: CGFloat = 120

    @AccessibilityFocusState private var answerFocused: Bool

    private var config: SessionConfig? { session?.config }

    var body: some View {
        ZStack {
            AppColor.page.ignoresSafeArea()
            if let session, let config {
                if session.status != .active {
                    summaryView(session)
                } else if session.currentPresentationID == nil {
                    waitingView(session, config: config)
                } else if let card {
                    GeometryReader { proxy in
                        let mode = AppMetrics.LayoutMode.resolve(width: proxy.size.width)
                        if mode == .compact || dynamicTypeSize.isAccessibilitySize {
                            compactReview(session, card: card, config: config)
                        } else {
                            expandedReview(session, card: card, config: config, mode: mode)
                        }
                    }
                } else {
                    missingCardView(session)
                }
            } else if let loadError {
                errorView(loadError)
            } else {
                ProgressView()
                    .tint(AppColor.accent)
            }
        }
        .preferredColorScheme(app.preferences.preferences.appearance.colorScheme)
        .onAppear {
            NotificationInbox.shared.activeReviewStackID = session?.stackID
        }
        .onDisappear {
            if let session, session.status == .active {
                app.review.pause(session)
            }
            if NotificationInbox.shared.activeReviewStackID == session?.stackID {
                NotificationInbox.shared.activeReviewStackID = nil
            }
        }
        .task {
            loadSession()
        }
        .onChange(of: session?.currentPresentationID) { _, _ in
            dragOffset = .zero
            didCrossSwipeThreshold = false
        }
        .sheet(isPresented: $showSettings) {
            if let session {
                NavigationStack {
                    StackSettingsView(stackID: session.stackID, showsClose: true)
                        .environment(app)
                }
            }
        }
        .onChange(of: showSettings) { _, isShowing in
            if !isShowing, let session, session.status == .active {
                app.review.resume(session)
            }
        }
        .confirmationDialog(
            "End this session?",
            isPresented: $showEndConfirmation,
            titleVisibility: .visible
        ) {
            Button("End session", role: .destructive) {
                guard let session else { return }
                _ = app.review.endSession(session)
                ratingLocked = false
            }
            Button("Continue learning", role: .cancel) {}
        } message: {
            Text("Completed ratings are kept. The ungraded card is discarded.")
        }
    }

    // MARK: Session loading

    private func loadSession() {
        guard !reviewStarted else { return }
        reviewStarted = true
        guard let loaded = app.review.session(id: sessionID) else {
            loadError = "This review session is no longer available."
            return
        }
        session = loaded
        NotificationInbox.shared.activeReviewStackID = loaded.stackID
        app.review.repair(loaded)
        card = app.review.currentCard(for: loaded)
        now = Date()
        if loaded.status == .active {
            app.review.resume(loaded)
        }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-DebugReveal"), loaded.status == .active {
            _ = app.review.reveal(loaded)
        }
        #endif
    }

    // MARK: Compact layout

    private func compactReview(_ session: ReviewSession, card: VocabularyCard, config: SessionConfig) -> some View {
        VStack(spacing: 0) {
            topBar(session)
            VStack(spacing: 12) {
                progressHeader(session)
                ScrollView {
                    VStack(spacing: 12) {
                        reviewCard(session, card: card, config: config, expanded: false)
                        RepeatDots(
                            count: card.learningState?.repeatCount ?? 0,
                            threshold: config.rules.correctThreshold,
                            currentIndex: min(card.learningState?.repeatCount ?? 0, max(0, config.rules.correctThreshold - 1))
                        )
                    }
                    .padding(.horizontal, 20)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
            .padding(.top, 6)
            actionArea(session, card: card, config: config)
        }
        .padding(.bottom, 4)
    }

    // MARK: Expanded layout

    private func expandedReview(
        _ session: ReviewSession,
        card: VocabularyCard,
        config: SessionConfig,
        mode: AppMetrics.LayoutMode
    ) -> some View {
        VStack(spacing: 0) {
            topBar(session)
            HStack(alignment: .top, spacing: mode.gap) {
                queueSidebar(session, config: config, width: mode == .duo ? 220 : 272)
                ScrollView {
                    VStack(spacing: 14) {
                        elapsedHeader(session)
                        reviewCard(session, card: card, config: config, expanded: true)
                        RepeatDots(
                            count: card.learningState?.repeatCount ?? 0,
                            threshold: config.rules.correctThreshold,
                            currentIndex: min(card.learningState?.repeatCount ?? 0, max(0, config.rules.correctThreshold - 1))
                        )
                        actionArea(session, card: card, config: config)
                    }
                    .frame(maxWidth: mode == .pad ? 452 : 346)
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(maxWidth: 820, alignment: .top)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, mode.inset)
            .padding(.bottom, 12)
        }
    }

    private func topBar(_ session: ReviewSession) -> some View {
        HStack(spacing: 8) {
            Button {
                if session.status == .active {
                    showEndConfirmation = true
                } else {
                    onClose()
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AppColor.textPrimary)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close review")
            .accessibilityIdentifier("review.close")

            Spacer()

            if session.status == .active {
                VStack(spacing: 1) {
                    Text("\(session.distinctPosition) of \(max(1, app.review.distinctCount(session)))")
                        .font(AppFont.font(14, .semibold))
                        .foregroundStyle(AppColor.textPrimary)
                        .monospacedDigit()
                    Text("cards")
                        .font(AppFont.font(9, .medium))
                        .foregroundStyle(AppColor.textSecondary)
                }
            }

            Spacer()

            Button {
                app.review.pause(session)
                showSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(AppColor.textSecondary)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Session settings")
            .accessibilityIdentifier("review.settings")
        }
        .padding(.horizontal, 12)
        .frame(height: 54)
    }

    private func progressHeader(_ session: ReviewSession) -> some View {
        VStack(spacing: 6) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(AppColor.divider)
                    Capsule()
                        .fill(AppColor.accent)
                        .frame(width: proxy.size.width * progressFraction(session))
                }
            }
            .frame(height: 5)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Session progress")
            .accessibilityValue("\(session.distinctPosition) of \(max(1, app.review.distinctCount(session)))")
        }
        .padding(.horizontal, 20)
    }

    private func progressFraction(_ session: ReviewSession) -> Double {
        let total = max(1, app.review.distinctCount(session))
        return min(1, max(0, Double(session.distinctPosition - (session.currentPresentationID == nil ? 0 : 1)) / Double(total)))
    }

    private func elapsedHeader(_ session: ReviewSession) -> some View {
        TimelineView(.periodic(from: Date(timeIntervalSinceReferenceDate: 0), by: 1)) { context in
            HStack {
                Text("Review in progress")
                    .font(AppFont.font(12, .semibold))
                    .foregroundStyle(AppColor.textSecondary)
                Spacer()
                Label(elapsedText(app.review.elapsedSeconds(session, at: context.date)), systemImage: "clock")
                    .font(AppFont.font(12, .medium))
                    .foregroundStyle(AppColor.textSecondary)
                    .monospacedDigit()
            }
        }
    }

    private func queueSidebar(_ session: ReviewSession, config: SessionConfig, width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Queue")
            let queue = session.queue()
            let upcoming = queue.presentations
                .filter { $0.gradedAt == nil && $0.id != session.currentPresentationID }
                .prefix(6)
            VStack(spacing: 6) {
                ForEach(Array(upcoming), id: \.id) { presentation in
                    if let queued = app.library.card(id: presentation.cardID) {
                        HStack(spacing: 8) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(presentation.isRetry ? AppColor.peach : AppColor.divider)
                                .frame(width: 3, height: 30)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(promptText(card: queued, config: config))
                                    .font(AppFont.font(12, .semibold))
                                    .foregroundStyle(AppColor.textPrimary)
                                    .lineLimit(1)
                                Text(LocalizedStringKey(presentation.isRetry ? "repeat" : "next"))
                                    .font(AppFont.font(9, .regular))
                                    .foregroundStyle(AppColor.textSecondary)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(8)
                        .background(AppColor.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Upcoming \(presentation.isRetry ? "repeat" : "card"): \(promptText(card: queued, config: config))")
                    }
                }
                if upcoming.isEmpty {
                    Text("No cards waiting")
                        .font(AppFont.caption())
                        .foregroundStyle(AppColor.textMuted)
                        .padding(.vertical, 12)
                }
            }
            Spacer()
        }
        .frame(width: width, alignment: .leading)
        .padding(.top, 6)
    }

    private func actionArea(_ session: ReviewSession, card: VocabularyCard, config: SessionConfig) -> some View {
        VStack(spacing: 8) {
            if !session.showingBack {
                PrimaryActionButton(title: "Show answer", systemImage: "eye", isEnabled: true) {
                    flip(session)
                }
                .padding(.horizontal, session.status == .active ? 20 : 0)
                .accessibilityIdentifier("review.reveal")
            } else {
                HStack(spacing: 16) {
                    Button {
                        rate(session, grade: .again)
                    } label: {
                        VStack(spacing: 2) {
                            Text("Again")
                                .font(AppFont.primaryAction())
                            Text("reset")
                                .font(AppFont.font(10, .regular))
                                .opacity(0.8)
                        }
                        .foregroundStyle(AppColor.danger)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(AppColor.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(AppColor.divider, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .disabled(ratingLocked)
                    .accessibilityIdentifier("review.again")

                    Button {
                        rate(session, grade: .good)
                    } label: {
                        VStack(spacing: 2) {
                            Text("Good")
                                .font(AppFont.primaryAction())
                            Text("remembered")
                                .font(AppFont.font(10, .regular))
                        }
                        .foregroundStyle(AppColor.onAccent)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(AppColor.accentStrong, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(ratingLocked)
                    .accessibilityIdentifier("review.good")
                }
                .padding(.horizontal, 20)
                .opacity(ratingLocked ? 0.72 : 1)
            }
            Button {
                showEndConfirmation = true
            } label: {
                Text("End session")
                    .font(AppFont.font(13, .medium))
                    .foregroundStyle(AppColor.textSecondary)
                    .frame(minHeight: 40)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("review.end")
        }
        .padding(.top, 4)
    }

    // MARK: Review card

    private func reviewCard(
        _ session: ReviewSession,
        card: VocabularyCard,
        config: SessionConfig,
        expanded: Bool
    ) -> some View {
        let state = card.learningState?.snapshot ?? .fresh
        let isRetry = session.currentPresentation()?.isRetry ?? false
        let showingBack = session.showingBack
        let swipeProgress = min(1, abs(dragOffset.width) / swipeThreshold)
        let content = VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(LocalizedStringKey(isRetry ? "REPEAT · \(state.lifecycle.title.uppercased())" : state.lifecycle == .new ? "NEW CARD" : state.lifecycle.title.uppercased()))
                    .font(AppFont.font(9.5, .semibold))
                    .tracking(1.1)
                    .foregroundStyle(AppColor.accentInk)
                Spacer()
                Text("\(state.repeatCount) / \(config.rules.correctThreshold) repeats")
                    .font(AppFont.font(10.5, .medium))
                    .foregroundStyle(AppColor.textSecondary)
                    .monospacedDigit()
            }
            .padding(.horizontal, 18)
            .frame(height: 44)
            .background(AppColor.accentSoft)

            Spacer(minLength: expanded ? 34 : 24)

            ZStack {
                frontContent(card: card, config: config, expanded: expanded)
                    .opacity(showingBack ? 0 : 1)
                    .rotation3DEffect(
                        .degrees(showingBack ? -180 : 0),
                        axis: (x: 0, y: 1, z: 0),
                        perspective: 0.55
                    )
                    .accessibilityHidden(true)
                backContent(card: card, config: config, expanded: expanded)
                    .opacity(showingBack ? 1 : 0)
                    .rotation3DEffect(
                        .degrees(showingBack ? 0 : 180),
                        axis: (x: 0, y: 1, z: 0),
                        perspective: 0.55
                    )
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, minHeight: expanded ? 370 : 280)
            .animation(.easeInOut(duration: 0.46), value: showingBack)

            Spacer(minLength: expanded ? 34 : 24)

            HStack(spacing: 6) {
                Image(systemName: showingBack ? "arrow.triangle.2.circlepath" : "hand.tap")
                Text(LocalizedStringKey(showingBack ? "Tap to flip back · swipe left or right to rate" : "Tap the card or Show answer"))
            }
            .font(AppFont.font(11.5, .regular))
            .foregroundStyle(AppColor.textMuted)
            .padding(.bottom, 18)
            .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, minHeight: expanded ? 560 : 420)
        .background(AppColor.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(AppColor.divider, lineWidth: 1))
        .shadow(color: AppColor.shadow.opacity(app.preferences.preferences.appearance == .dark ? 0.4 : 0.08), radius: 14, x: 0, y: 8)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

        let cardLabel = showingBack
            ? backAccessibilityLabel(card: card, config: config)
            : frontAccessibilityLabel(card: card, config: config)

        return content
            .overlay(alignment: .topLeading) {
                swipeStamp(
                    text: "AGAIN",
                    color: AppColor.danger,
                    opacity: dragOffset.width < 0 ? swipeProgress : 0,
                    rotation: -11
                )
            }
            .overlay(alignment: .topTrailing) {
                swipeStamp(
                    text: "GOOD",
                    color: AppColor.success,
                    opacity: dragOffset.width > 0 ? swipeProgress : 0,
                    rotation: 11
                )
            }
            .offset(dragOffset)
            .rotationEffect(.degrees(max(-12, min(12, Double(dragOffset.width / 22)))))
            .scaleEffect(1 - min(abs(dragOffset.width) / 4_000, 0.04))
            .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .onTapGesture {
                flip(session)
            }
            .simultaneousGesture(cardDragGesture(session))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(cardLabel)
            .accessibilityHint(showingBack ? "Double tap to flip back. Use Again or Good to rate." : "Double tap to flip the card and show the answer.")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction {
                flip(session)
            }
            .accessibilityIdentifier("review.card")
    }

    private func swipeStamp(text: String, color: Color, opacity: Double, rotation: Double) -> some View {
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

    private func cardDragGesture(_ session: ReviewSession) -> some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                guard session.showingBack, !ratingLocked, !isThrowing else { return }
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                dragOffset = CGSize(
                    width: value.translation.width,
                    height: value.translation.height * 0.25
                )
                let crossed = abs(value.translation.width) >= swipeThreshold
                if crossed && !didCrossSwipeThreshold {
                    didCrossSwipeThreshold = true
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                } else if !crossed {
                    didCrossSwipeThreshold = false
                }
            }
            .onEnded { value in
                guard session.showingBack, !ratingLocked, !isThrowing else {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        dragOffset = .zero
                    }
                    didCrossSwipeThreshold = false
                    return
                }
                let horizontal = value.translation.width
                guard abs(horizontal) >= swipeThreshold,
                      abs(horizontal) > abs(value.translation.height) else {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        dragOffset = .zero
                    }
                    didCrossSwipeThreshold = false
                    return
                }
                throwCard(session, grade: horizontal > 0 ? .good : .again)
            }
    }

    private func throwCard(_ session: ReviewSession, grade: ReviewGrade) {
        guard !ratingLocked, !isThrowing else { return }
        isThrowing = true
        didCrossSwipeThreshold = false
        let direction: CGFloat = grade == .good ? 1 : -1
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        withAnimation(.easeOut(duration: 0.28)) {
            dragOffset = CGSize(width: direction * 900, height: dragOffset.height)
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(260))
            rate(session, grade: grade)
            dragOffset = .zero
            isThrowing = false
        }
    }

    private func frontContent(card: VocabularyCard, config: SessionConfig, expanded: Bool) -> some View {
        let prompt = config.translationFirst ? card.translation : card.word
        let example = config.translationFirst ? card.translatedExample : card.sourceExample
        return VStack(spacing: 8) {
            if !config.translationFirst, let phonetic = card.phonetic, !phonetic.isEmpty {
                Text(phonetic)
                    .font(AppFont.font(13, .regular))
                    .foregroundStyle(AppColor.textSecondary)
            }
            Text(prompt)
                .font(AppFont.frontWord())
                .foregroundStyle(AppColor.textPrimary)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.55)
                .lineLimit(4)
                .padding(.horizontal, 20)
            if !config.translationFirst, let pos = card.partOfSpeech, expanded {
                partOfSpeechChips(pos)
            }
            if let example, !example.isEmpty {
                Text(example)
                    .font(AppFont.font(15, .regular))
                    .foregroundStyle(AppColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(4)
                    .padding(.horizontal, 26)
                    .padding(.top, 4)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityPrompt(prompt: prompt, phonetic: config.translationFirst ? nil : card.phonetic, example: example))
    }

    private func backContent(card: VocabularyCard, config: SessionConfig, expanded: Bool) -> some View {
        let answer = config.translationFirst ? card.word : card.translation
        let answerExample = config.translationFirst ? card.sourceExample : card.translatedExample
        let prompt = config.translationFirst ? card.translation : card.word
        let promptExample = config.translationFirst ? card.translatedExample : card.sourceExample
        return VStack(spacing: 10) {
            Text(answer)
                .font(AppFont.backTranslation())
                .foregroundStyle(AppColor.textPrimary)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.55)
                .lineLimit(4)
                .padding(.horizontal, 20)
                .accessibilityFocused($answerFocused)
            if let answerExample, !answerExample.isEmpty {
                Text(answerExample)
                    .font(AppFont.font(15, .regular))
                    .foregroundStyle(AppColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .padding(.horizontal, 26)
            }
            Rectangle()
                .fill(AppColor.divider)
                .frame(height: 1)
                .padding(.horizontal, 36)
                .padding(.vertical, 4)
            Text(prompt)
                .font(AppFont.font(17, .semibold))
                .foregroundStyle(AppColor.textPrimary)
            if !config.translationFirst, let phonetic = card.phonetic, !phonetic.isEmpty {
                Text(phonetic)
                    .font(AppFont.font(12, .regular))
                    .foregroundStyle(AppColor.textSecondary)
            }
            if let promptExample, !promptExample.isEmpty {
                Text(promptExample)
                    .font(AppFont.font(12.5, .regular))
                    .foregroundStyle(AppColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .padding(.horizontal, 26)
            }
            if expanded, let pos = card.partOfSpeech {
                partOfSpeechChips(pos)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityPrompt(prompt: answer, phonetic: nil, example: answerExample))
    }

    private func partOfSpeechChips(_ value: String) -> some View {
        let chips = value.split(separator: " ").flatMap { $0.split(separator: ",") }.map(String.init)
        return HStack(spacing: 6) {
            ForEach(chips, id: \.self) { chip in
                Text(chip)
                    .font(AppFont.font(10, .semibold))
                    .foregroundStyle(AppColor.accentInk)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(AppColor.accentSoft, in: Capsule())
            }
        }
    }

    // MARK: Summary / waiting / errors

    private func summaryView(_ session: ReviewSession) -> some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(AppColor.textPrimary)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            }
            .padding(.horizontal, 12)

            Spacer()
            VStack(spacing: 16) {
                Image(systemName: "checkmark")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(AppColor.onAccent)
                    .frame(width: 58, height: 58)
                    .background(Circle().fill(AppColor.accentStrong))
                Text("Session complete")
                    .font(AppFont.screenTitle())
                    .foregroundStyle(AppColor.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Text("Completed answers are saved. Unfinished cards stay in your library.")
                    .font(AppFont.body())
                    .foregroundStyle(AppColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            HStack(spacing: 10) {
                StatCard(count: app.review.totalReviewed(session), label: "Reviewed")
                StatCard(count: session.goodCount, label: "Good")
                StatCard(count: session.againCount, label: "Again")
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)

            Spacer()

            PrimaryActionButton(title: "Done", systemImage: "checkmark") {
                onClose()
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
            .accessibilityIdentifier("review.done")
        }
    }

    private func waitingView(_ session: ReviewSession, config: SessionConfig) -> some View {
        let next = session.queue().nextRetryAt ?? Date()
        return VStack(spacing: 0) {
            topBar(session)
            Spacer()
            TimelineView(.periodic(from: Date(timeIntervalSinceReferenceDate: 0), by: 1)) { context in
                VStack(spacing: 14) {
                    Image(systemName: "clock.badge.checkmark")
                        .font(.system(size: 34, weight: .light))
                        .foregroundStyle(AppColor.accentStrong)
                    Text("Almost ready")
                        .font(AppFont.screenTitle())
                        .foregroundStyle(AppColor.textPrimary)
                    Text("Other cards are finished. The next repeat becomes available shortly.")
                        .font(AppFont.body())
                        .foregroundStyle(AppColor.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                    Text(countdownText(next.timeIntervalSince(context.date)))
                        .font(AppFont.font(34, .semibold))
                        .foregroundStyle(AppColor.accentStrong)
                        .monospacedDigit()
                        .accessibilityLabel("Next review in \(countdownText(next.timeIntervalSince(context.date)))")
                }
                .onChange(of: context.date) { _, date in
                    if date >= next {
                        if app.review.advanceIfPossible(session) {
                            refresh(session)
                        }
                    }
                }
            }
            Spacer()
            VStack(spacing: 8) {
                PrimaryActionButton(title: "End session", isEnabled: true) {
                    _ = app.review.endSession(session)
                }
                .accessibilityIdentifier("review.waiting.end")
                Text("You can finish now. Ratings already saved are kept.")
                    .font(AppFont.caption())
                    .foregroundStyle(AppColor.textSecondary)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
    }

    private func missingCardView(_ session: ReviewSession) -> some View {
        VStack(spacing: 0) {
            topBar(session)
            Spacer()
            EmptyStateView(
                title: "This card is no longer available",
                message: "It was deleted or moved while the session was open.",
                actionTitle: "End session",
                action: { _ = app.review.endSession(session) }
            )
            Spacer()
        }
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 34))
                .foregroundStyle(AppColor.accentStrong)
            Text(LocalizedStringKey(message))
                .font(AppFont.body())
                .foregroundStyle(AppColor.textSecondary)
                .multilineTextAlignment(.center)
            PrimaryActionButton(title: "Back to words") { onClose() }
                .frame(maxWidth: 280)
        }
        .padding(28)
    }

    // MARK: Actions

    private func flip(_ session: ReviewSession) {
        guard !ratingLocked, !isThrowing else { return }
        guard session.status == .active, session.currentPresentationID != nil else { return }
        let target = !session.showingBack
        withAnimation(.easeInOut(duration: 0.46)) {
            _ = app.review.setShowingBack(session, showing: target)
        }
        now = Date()
        if target {
            answerFocused = true
            UIAccessibility.post(notification: .announcement, argument: app.localized("Answer shown"))
        } else {
            UIAccessibility.post(notification: .announcement, argument: app.localized("Question shown"))
        }
    }

    private func rate(_ session: ReviewSession, grade: ReviewGrade) {
        guard !ratingLocked else { return }
        ratingLocked = true
        let result = app.review.grade(session, grade: grade)
        switch result {
        case .advanced:
            card = app.review.currentCard(for: session)
            now = Date()
            UIAccessibility.post(notification: .announcement, argument: app.localized(grade == .good ? "Good saved" : "Again saved"))
        case .completed:
            card = nil
            UIAccessibility.post(notification: .announcement, argument: app.localized("Session complete"))
        case .waiting:
            card = nil
        case .skipped(let reason):
            card = app.review.currentCard(for: session)
            if let reason { app.router.showToast(reason) }
        case .duplicate:
            break
        case .failure(let message):
            app.router.showToast(message)
        }
        ratingLocked = false
    }

    private func refresh(_ session: ReviewSession) {
        card = app.review.currentCard(for: session)
        now = Date()
    }

    private func promptText(card: VocabularyCard, config: SessionConfig) -> String {
        config.translationFirst ? card.translation : card.word
    }

    private func accessibilityPrompt(prompt: String, phonetic: String?, example: String?) -> String {
        var parts = [prompt]
        if let phonetic, !phonetic.isEmpty { parts.append(phonetic) }
        if let example, !example.isEmpty { parts.append(example) }
        return parts.joined(separator: ", ")
    }

    private func frontAccessibilityLabel(card: VocabularyCard, config: SessionConfig) -> String {
        let prompt = config.translationFirst ? card.translation : card.word
        let example = config.translationFirst ? card.translatedExample : card.sourceExample
        return accessibilityPrompt(
            prompt: prompt,
            phonetic: config.translationFirst ? nil : card.phonetic,
            example: example
        )
    }

    private func backAccessibilityLabel(card: VocabularyCard, config: SessionConfig) -> String {
        let answer = config.translationFirst ? card.word : card.translation
        let answerExample = config.translationFirst ? card.sourceExample : card.translatedExample
        let prompt = config.translationFirst ? card.translation : card.word
        let promptExample = config.translationFirst ? card.translatedExample : card.sourceExample
        let primary = accessibilityPrompt(prompt: answer, phonetic: nil, example: answerExample)
        let secondary = accessibilityPrompt(prompt: prompt, phonetic: nil, example: promptExample)
        return "\(primary), \(secondary)"
    }

    private func countdownText(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.up)))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private func elapsedText(_ seconds: Double) -> String {
        let total = max(0, Int(seconds))
        let hours = total / 3_600
        let minutes = (total % 3_600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }
}
