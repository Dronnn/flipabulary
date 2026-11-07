import SwiftUI

struct WidgetListRow: View {
    let card: WidgetCardSnapshot
    let showTranslation: Bool
    var compact: Bool = false

    var body: some View {
        HStack(spacing: compact ? 7 : 9) {
            InitialTile(word: card.word, id: card.id, size: compact ? 24 : 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(card.word)
                    .font(AppFont.font(compact ? 12 : 13, .semibold))
                    .foregroundStyle(AppColor.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if showTranslation {
                    Text(card.translation)
                        .font(AppFont.font(compact ? 9 : 10, .regular))
                        .foregroundStyle(AppColor.textSecondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 3)
            Text("\(card.repeatCount)/\(card.threshold)")
                .font(AppFont.font(compact ? 8 : 9, .medium))
                .foregroundStyle(AppColor.textSecondary)
                .monospacedDigit()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        var parts = [card.word]
        if showTranslation { parts.append(card.translation) }
        parts.append(card.lifecycle)
        parts.append("\(card.repeatCount) of \(card.threshold) repeats")
        return parts.joined(separator: ", ")
    }
}

struct WidgetCardTile: View {
    let card: WidgetCardSnapshot
    var showTranslation: Bool = true

    var body: some View {
        HStack(spacing: 8) {
            InitialTile(word: card.word, id: card.id, size: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(card.word)
                    .font(AppFont.font(13, .semibold))
                    .foregroundStyle(AppColor.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                if showTranslation {
                    Text(card.translation)
                        .font(AppFont.font(10, .regular))
                        .foregroundStyle(AppColor.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
            }
            Spacer(minLength: 2)
            RepeatBars(count: card.repeatCount, threshold: card.threshold, barWidth: 2, height: 9)
        }
    }
}

struct WidgetWordmark: View {
    var body: some View {
        Text("WORDS")
            .font(AppFont.font(9, .semibold))
            .tracking(2)
            .foregroundStyle(AppColor.textSecondary)
            .accessibilityHidden(true)
    }
}
