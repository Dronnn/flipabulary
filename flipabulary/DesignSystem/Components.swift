import SwiftUI

// MARK: - Layout shells

struct PageBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(AppColor.page.ignoresSafeArea())
    }
}

extension View {
    func pageBackground() -> some View { modifier(PageBackground()) }
}

struct ScreenTitle: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(LocalizedStringKey(title))
                .font(AppFont.largeTitle())
                .foregroundStyle(AppColor.textPrimary)
                .accessibilityAddTraits(.isHeader)
            if let subtitle {
                Text(LocalizedStringKey(subtitle))
                    .font(AppFont.font(13, .regular))
                    .foregroundStyle(AppColor.textSecondary)
            }
        }
    }
}

struct SectionHeader: View {
    let title: String
    var body: some View {
        Text(LocalizedStringKey(title))
            .sectionLabelStyle()
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Buttons

struct CircleIconButton: View {
    let systemName: String
    let accessibilityLabel: String
    var filled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(filled ? AppColor.onAccent : AppColor.textPrimary)
                .frame(width: 44, height: 44)
                .background {
                    Circle()
                        .fill(filled ? AppColor.accentStrong : AppColor.surface)
                        .shadow(color: AppColor.shadow.opacity(0.08), radius: 12, y: 8)
                }
                .overlay {
                    if !filled {
                        Circle().stroke(AppColor.divider, lineWidth: 1)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

struct PrimaryActionButton: View {
    let title: String
    var systemImage: String?
    var isEnabled: Bool = true
    var isWorking: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isWorking {
                    ProgressView().tint(AppColor.onAccent)
                } else if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(LocalizedStringKey(title))
            }
            .font(AppFont.primaryAction())
            .foregroundStyle(AppColor.onAccent)
            .frame(maxWidth: .infinity)
            .frame(height: AppMetrics.actionHeight)
            .background(
                RoundedRectangle(cornerRadius: AppMetrics.primaryRadius, style: .continuous)
                    .fill(isEnabled ? AppColor.accentStrong : AppColor.textMuted.opacity(0.55))
            )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled || isWorking)
    }
}

struct SecondaryActionButton: View {
    let title: String
    var systemImage: String?
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let systemImage { Image(systemName: systemImage) }
                Text(LocalizedStringKey(title))
            }
            .font(AppFont.font(15, .semibold))
            .foregroundStyle(isEnabled ? AppColor.textPrimary : AppColor.textMuted)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(AppColor.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(AppColor.divider, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }
}

struct TextLinkButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(LocalizedStringKey(title))
                .font(AppFont.font(14, .semibold))
                .foregroundStyle(AppColor.accentStrong)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Controls

struct SearchField: View {
    let placeholder: String
    @Binding var text: String
    var accessibilityIdentifier: String = "words.search"

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(AppColor.textSecondary)
                .frame(width: 16, height: 16)
                .accessibilityHidden(true)
            TextField("", text: $text, prompt: Text(LocalizedStringKey(placeholder)).foregroundStyle(AppColor.textMuted))
                .font(AppFont.font(15, .regular))
                .foregroundStyle(AppColor.textPrimary)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityIdentifier(accessibilityIdentifier)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(AppColor.textMuted)
                        .frame(width: 28, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, 6)
        .frame(height: 44)
        .background(
            RoundedRectangle(cornerRadius: AppMetrics.fieldRadius, style: .continuous)
                .fill(AppColor.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppMetrics.fieldRadius, style: .continuous)
                .stroke(AppColor.divider, lineWidth: 1)
        )
    }
}

struct FilterChip: View {
    let title: String
    var count: Int?
    let isSelected: Bool
    let action: () -> Void
    var accessibilityIdentifier: String?

    var body: some View {
        Button(action: action) {
            (Text(LocalizedStringKey(title)) + (count.map { Text(verbatim: " \($0)") } ?? Text(verbatim: "")))
                .font(AppFont.font(13, .medium))
                .foregroundStyle(isSelected ? AppColor.onAccent : AppColor.textPrimary)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .frame(minHeight: 32)
            .background(
                Capsule()
                    .fill(isSelected ? AppColor.accentInk : AppColor.surface)
            )
            .overlay(
                Capsule().stroke(isSelected ? .clear : AppColor.divider, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier(accessibilityIdentifier ?? "words.filter.\(title.lowercased())")
    }
}

struct CompactToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            ZStack {
                Capsule()
                    .fill(configuration.isOn ? AppColor.accent : AppColor.divider)
                    .frame(width: 51, height: 31)
                Circle()
                    .fill(AppColor.surface)
                    .frame(width: 27, height: 27)
                    .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
                    .offset(x: configuration.isOn ? 10 : -10)
            }
            .frame(width: 51, height: 44, alignment: .trailing)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityRepresentation {
            Toggle(
                isOn: Binding(
                    get: { configuration.isOn },
                    set: { configuration.isOn = $0 }
                )
            ) {
                configuration.label
            }
        }
    }
}

struct StepperCapsule: View {
    let label: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    var accessibilityIdentifier: String?

    var body: some View {
        HStack(spacing: 0) {
            Button {
                value = max(range.lowerBound, value - 1)
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .disabled(value <= range.lowerBound)
            .accessibilityLabel("Decrease \(label)")

            Text("\(value)")
                .font(AppFont.font(15, .semibold))
                .monospacedDigit()
                .foregroundStyle(AppColor.textPrimary)
                .frame(minWidth: 24)
                .accessibilityHidden(true)

            Button {
                value = min(range.upperBound, value + 1)
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .disabled(value >= range.upperBound)
            .accessibilityLabel("Increase \(label)")
        }
        .foregroundStyle(AppColor.textPrimary)
        .background(
            Capsule()
                .fill(AppColor.accentSoft)
                .frame(height: 31)
        )
        .overlay(
            Capsule().stroke(AppColor.divider, lineWidth: 1).frame(height: 31)
        )
        .frame(width: 112, height: 44)
        .accessibilityElement(children: .contain)
        .accessibilityValue("\(value)")
        .accessibilityIdentifier(accessibilityIdentifier ?? "")
    }
}

struct AppearanceSelector: View {
    @Binding var selection: AppearancePreference

    var body: some View {
        HStack(spacing: 4) {
            ForEach(AppearancePreference.allCases) { preference in
                Button {
                    selection = preference
                } label: {
                    Text(LocalizedStringKey(preference.title))
                        .font(AppFont.font(13, .semibold))
                        .foregroundStyle(selection == preference ? AppColor.onAccent : AppColor.textSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(selection == preference ? AppColor.accentStrong : .clear)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == preference ? .isSelected : [])
                .accessibilityIdentifier("settings.appearance.\(preference.rawValue)")
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(AppColor.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(AppColor.divider, lineWidth: 1)
        )
    }
}

// MARK: - Surfaces

struct GroupedSurface<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .background(
            RoundedRectangle(cornerRadius: AppMetrics.cardRadius, style: .continuous)
                .fill(AppColor.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppMetrics.cardRadius, style: .continuous)
                .stroke(AppColor.divider, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: AppMetrics.cardRadius, style: .continuous))
    }
}

struct SettingsRow: View {
    let title: String
    var value: String?
    var detail: String?
    var showsChevron: Bool = true
    var isDestructive: Bool = false
    var action: (() -> Void)?

    var body: some View {
        Group {
            if let action {
                Button(action: action) { rowContent }
                    .buttonStyle(.plain)
            } else {
                rowContent
            }
        }
        .frame(minHeight: 52)
        .contentShape(Rectangle())
    }

    private var rowContent: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(LocalizedStringKey(title))
                    .font(AppFont.fieldValue())
                    .foregroundStyle(isDestructive ? AppColor.danger : AppColor.textPrimary)
                if let detail {
                    Text(LocalizedStringKey(detail))
                        .font(AppFont.caption())
                        .foregroundStyle(AppColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            if let value {
                Text(value)
                    .font(AppFont.font(14, .regular))
                    .foregroundStyle(AppColor.textSecondary)
            }
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppColor.textMuted)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

struct SettingsDivider: View {
    var inset: CGFloat = 16
    var body: some View {
        Rectangle()
            .fill(AppColor.divider)
            .frame(height: 1)
            .padding(.leading, inset)
    }
}

struct StatCard: View {
    let count: Int
    let label: String
    var accessibilityIdentifier: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("\(count)")
                .font(AppFont.statCount())
                .foregroundStyle(AppColor.textPrimary)
                .monospacedDigit()
            Text(LocalizedStringKey(label))
                .font(AppFont.font(12, .medium))
                .foregroundStyle(AppColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(minHeight: 64)
        .raisedSurface(radius: 16)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label), \(count)")
        .accessibilityIdentifier(accessibilityIdentifier ?? "")
    }
}

struct EmptyStateView: View {
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 10) {
            Text(LocalizedStringKey(title))
                .font(AppFont.font(18, .semibold))
                .foregroundStyle(AppColor.textPrimary)
                .multilineTextAlignment(.center)
            Text(LocalizedStringKey(message))
                .font(AppFont.body())
                .foregroundStyle(AppColor.textSecondary)
                .multilineTextAlignment(.center)
            if let actionTitle, let action {
                TextLinkButton(title: actionTitle, action: action)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .padding(.horizontal, 24)
    }
}

struct InlineMessage: View {
    enum Kind { case error, info, success }

    let text: String
    var kind: Kind = .error

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
            Text(LocalizedStringKey(text))
                .font(AppFont.font(12, .regular))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .foregroundStyle(color)
        .padding(12)
        .background(color.opacity(0.09), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var icon: String {
        switch kind {
        case .error: "exclamationmark.circle.fill"
        case .info: "info.circle.fill"
        case .success: "checkmark.circle.fill"
        }
    }

    private var color: Color {
        switch kind {
        case .error: AppColor.danger
        case .info: AppColor.textSecondary
        case .success: AppColor.success
        }
    }
}

// MARK: - Word presentation

struct WordProgressBadge: View {
    let count: Int
    let threshold: Int

    var body: some View {
        VStack(alignment: .trailing, spacing: 5) {
            Text("\(count) / \(threshold)")
                .font(AppFont.font(11, .semibold))
                .foregroundStyle(AppColor.textSecondary)
                .monospacedDigit()
            RepeatBars(count: count, threshold: threshold)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(count) of \(threshold) repeats")
    }
}

struct WordRow: View {
    let card: CardDisplayModel
    var showsChevron: Bool = true
    var action: (() -> Void)?

    var body: some View {
        Group {
            if let action {
                Button(action: action) { content }
                    .buttonStyle(.plain)
            } else {
                content
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(.isButton)
    }

    private var content: some View {
        HStack(spacing: 12) {
            InitialTile(word: card.word, id: card.id)
            VStack(alignment: .leading, spacing: 3) {
                Text(card.word)
                    .font(AppFont.rowWord())
                    .foregroundStyle(AppColor.textPrimary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                Text(card.translation)
                    .font(AppFont.rowTranslation())
                    .foregroundStyle(AppColor.textSecondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            WordProgressBadge(count: card.repeatCount, threshold: card.threshold)
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppColor.textMuted)
            }
        }
        .frame(minHeight: 76)
        .padding(.horizontal, 16)
        .contentShape(Rectangle())
    }

    private var accessibilityLabel: String {
        var parts = [card.word, card.translation, card.lifecycle.title, "\(card.repeatCount) of \(card.threshold) repeats"]
        if card.isDifficult { parts.append("Difficult") }
        return parts.joined(separator: ", ")
    }
}

struct CardPreview: View {
    let card: CardDisplayModel?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Preview")
            GroupedSurface {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        if let card {
                            InitialTile(word: card.word, id: card.id, size: 40)
                        } else {
                            RoundedRectangle(cornerRadius: 12).fill(AppColor.accentSoft).frame(width: 40, height: 40)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(card?.word.isEmpty == false ? card!.word : "Your word")
                                .font(AppFont.font(22, .semibold))
                                .foregroundStyle(AppColor.textPrimary)
                            if let phonetic = card?.phonetic, !phonetic.isEmpty {
                                Text(phonetic)
                                    .font(AppFont.font(12, .regular))
                                    .foregroundStyle(AppColor.textSecondary)
                            }
                        }
                        Spacer()
                        if let card, let pos = card.partOfSpeech {
                            Text(pos)
                                .font(AppFont.font(10, .semibold))
                                .foregroundStyle(AppColor.accentInk)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(AppColor.accentSoft, in: Capsule())
                        }
                    }
                    Divider().overlay(AppColor.divider)
                    Text(card?.translation.isEmpty == false ? card!.translation : "Translation")
                        .font(AppFont.font(24, .semibold))
                        .foregroundStyle(AppColor.textPrimary)
                    if let example = card?.sourceExample, !example.isEmpty {
                        Text(example)
                            .font(AppFont.body())
                            .foregroundStyle(AppColor.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let card {
                        HStack {
                            Text(card.stackName)
                                .font(AppFont.caption())
                                .foregroundStyle(AppColor.textSecondary)
                            Spacer()
                            RepeatBars(count: card.repeatCount, threshold: card.threshold)
                        }
                    }
                }
                .padding(18)
            }
        }
    }
}

struct CategoryTile: View {
    let summary: CategorySummary
    let total: Int
    let isSelected: Bool
    let action: () -> Void

    private var tint: Color {
        switch summary.filter {
        case .new: AppColor.blue
        case .learning: AppColor.sand
        case .learned: AppColor.mint
        case .difficult: AppColor.peach
        case .all: AppColor.accentSoft
        }
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(LocalizedStringKey(summary.filter.title))
                        .font(AppFont.font(13, .semibold))
                        .foregroundStyle(AppColor.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 6)
                    Text("\(summary.count)")
                        .font(AppFont.statCount())
                        .foregroundStyle(AppColor.textPrimary)
                        .fixedSize(horizontal: true, vertical: true)
                }
                Text("\(summary.count) / \(total)")
                    .font(AppFont.caption())
                    .foregroundStyle(AppColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(AppColor.divider)
                        Capsule()
                            .fill(AppColor.accent)
                            .frame(width: proxy.size.width * LibraryQuery.relativeRatio(count: summary.count, total: total))
                    }
                }
                .frame(height: 4)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tint, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isSelected ? AppColor.accent : .clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(summary.filter.title), \(summary.count) of \(total)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct DueHero: View {
    let due: Int
    let total: Int
    let label: String
    var ringSize: CGFloat = 110
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 18) {
                ZStack {
                    ProgressRing(
                        progress: LibraryQuery.relativeRatio(count: total - due, total: total),
                        lineWidth: max(8, ringSize * 0.08),
                        size: ringSize,
                        label: "\(total - due) of \(total) learned"
                    )
                    VStack(spacing: 0) {
                        Text("\(due)")
                            .font(AppFont.font(ringSize * 0.27, .semibold))
                            .foregroundStyle(AppColor.textPrimary)
                            .monospacedDigit()
                        Text("due")
                            .font(AppFont.caption())
                            .foregroundStyle(AppColor.textSecondary)
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(label)
                        .font(AppFont.font(20, .semibold))
                        .foregroundStyle(AppColor.textPrimary)
                    Text("\(total) saved words")
                        .font(AppFont.body())
                        .foregroundStyle(AppColor.textSecondary)
                    Text("Review")
                        .font(AppFont.font(13, .semibold))
                        .foregroundStyle(AppColor.accentStrong)
                }
                Spacer(minLength: 0)
            }
            .padding(18)
            .raisedSurface()
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Review \(due) due cards")
        .accessibilityAddTraits(.isButton)
    }
}

struct SettingsToggleRow: View {
    let title: String
    var detail: String?
    @Binding var isOn: Bool
    var accessibilityIdentifier: String?

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(LocalizedStringKey(title))
                    .font(AppFont.fieldValue())
                    .foregroundStyle(AppColor.textPrimary)
                if let detail {
                    Text(LocalizedStringKey(detail))
                        .font(AppFont.caption())
                        .foregroundStyle(AppColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer()
            Toggle(isOn: $isOn) {
                Text(LocalizedStringKey(title))
            }
                .labelsHidden()
                .toggleStyle(CompactToggleStyle())
                .accessibilityIdentifier(accessibilityIdentifier ?? "")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(minHeight: 52)
    }
}
