import SwiftUI

/// Mirrors the card face used by the review screen so onboarding shows the real product UI.
struct OnboardingReviewCardView: View {
    let word: String
    let translation: String
    let sourceExample: String?
    let translatedExample: String?
    let phonetic: String?
    let partOfSpeech: String?
    let stateTitle: String
    let repeatCount: Int
    let threshold: Int
    let showingBack: Bool
    let translationFirst: Bool
    let expanded: Bool
    var compact: Bool = false
    var showsBackHint: Bool = true

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(LocalizedStringKey(stateTitle))
                    .font(AppFont.font(9.5, .semibold))
                    .tracking(1.1)
                    .foregroundStyle(AppColor.accentInk)
                Spacer()
                Text("\(repeatCount) / \(threshold) repeats")
                    .font(AppFont.font(10.5, .medium))
                    .foregroundStyle(AppColor.textPrimary)
                    .monospacedDigit()
            }
            .padding(.horizontal, 18)
            .frame(height: compact ? 36 : 44)
            .background(AppColor.accentSoft)

            Spacer(minLength: compact ? 12 : (expanded ? 34 : 20))

            ZStack {
                frontContent
                    .opacity(showingBack ? 0 : 1)
                    .rotation3DEffect(
                        .degrees(showingBack ? -180 : 0),
                        axis: (x: 0, y: 1, z: 0),
                        perspective: 0.55
                    )
                    .accessibilityHidden(true)
                backContent
                    .opacity(showingBack ? 1 : 0)
                    .rotation3DEffect(
                        .degrees(showingBack ? 0 : 180),
                        axis: (x: 0, y: 1, z: 0),
                        perspective: 0.55
                    )
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, minHeight: compact ? 150 : (expanded ? 370 : 230))
            .animation(.easeInOut(duration: 0.46), value: showingBack)

            Spacer(minLength: compact ? 12 : (expanded ? 34 : 20))

            if !showingBack || showsBackHint {
                HStack(spacing: 6) {
                    Image(systemName: showingBack ? "arrow.triangle.2.circlepath" : "hand.tap")
                    Text(LocalizedStringKey(showingBack ? "Tap to flip back · swipe left or right to rate" : "Tap the card or Show answer"))
                }
                .font(AppFont.font(11.5, .regular))
                .foregroundStyle(AppColor.textMuted)
                .padding(.bottom, compact ? 10 : 18)
                .accessibilityHidden(true)
            } else {
                Color.clear.frame(height: compact ? 10 : 18)
            }
        }
        .frame(maxWidth: .infinity, minHeight: compact ? 280 : (expanded ? 560 : 370))
        .background(AppColor.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(AppColor.divider, lineWidth: 1))
        .shadow(color: AppColor.shadow.opacity(colorScheme == .dark ? 0.4 : 0.08), radius: 14, x: 0, y: 8)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var frontContent: some View {
        VStack(spacing: 8) {
            if !translationFirst, let phonetic, !phonetic.isEmpty {
                Text(phonetic)
                    .font(AppFont.font(13, .regular))
                    .foregroundStyle(AppColor.textSecondary)
            }
            Text(translationFirst ? translation : word)
                .font(AppFont.frontWord())
                .foregroundStyle(AppColor.textPrimary)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.55)
                .lineLimit(4)
                .padding(.horizontal, 20)
            if !translationFirst, let partOfSpeech, expanded {
                partOfSpeechChips(partOfSpeech)
            }
            if let example = translationFirst ? translatedExample : sourceExample,
               !example.isEmpty {
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
    }

    private var backContent: some View {
        VStack(spacing: 10) {
            Text(translationFirst ? word : translation)
                .font(AppFont.backTranslation())
                .foregroundStyle(AppColor.textPrimary)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.55)
                .lineLimit(4)
                .padding(.horizontal, 20)
            if let answerExample = translationFirst ? sourceExample : translatedExample,
               !answerExample.isEmpty {
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
            Text(translationFirst ? translation : word)
                .font(AppFont.font(17, .semibold))
                .foregroundStyle(AppColor.textPrimary)
            if !translationFirst, let phonetic, !phonetic.isEmpty {
                Text(phonetic)
                    .font(AppFont.font(12, .regular))
                    .foregroundStyle(AppColor.textSecondary)
            }
            if let promptExample = translationFirst ? translatedExample : sourceExample,
               !promptExample.isEmpty {
                Text(promptExample)
                    .font(AppFont.font(12.5, .regular))
                    .foregroundStyle(AppColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .padding(.horizontal, 26)
            }
            if expanded, let partOfSpeech {
                partOfSpeechChips(partOfSpeech)
            }
        }
        .accessibilityElement(children: .combine)
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
}
