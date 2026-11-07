import SwiftUI

struct SupportView: View {
    @Environment(AppEnvironment.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var model: SupportViewModel

    @MainActor
    init(purchasing: SupportPurchasing? = nil) {
        _model = State(initialValue: SupportViewModel(purchasing: purchasing ?? StoreKitSupportService()))
    }

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                let mode = AppMetrics.LayoutMode.resolve(width: proxy.size.width)
                ScrollView {
                    if mode == .compact || dynamicTypeSize.isAccessibilitySize {
                        compact
                    } else {
                        expanded(mode: mode)
                            .padding(.horizontal, mode.inset)
                    }
                }
                .pageBackground()
            }
            .navigationTitle("Support")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
            }
            .task {
                await model.load()
            }
        }
    }

    private var compact: some View {
        VStack(alignment: .leading, spacing: 18) {
            intro
            options
        }
        .padding(20)
    }

    private func expanded(mode: AppMetrics.LayoutMode) -> some View {
        HStack(alignment: .top, spacing: mode.gap) {
            VStack(alignment: .leading, spacing: 18) {
                intro
                finePrint
            }
            .frame(width: mode == .duo ? 230 : 300)
            options
        }
        .padding(.top, 20)
        .padding(.bottom, 28)
        .frame(maxWidth: 900)
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: "heart.fill")
                .font(.system(size: 42, weight: .regular))
                .foregroundStyle(AppColor.accentStrong)
                .frame(width: 56, height: 56)
                .background(AppColor.accentSoft, in: Circle())
                .accessibilityHidden(true)
            Text("Support Flipabulary")
                .font(AppFont.screenTitle())
                .foregroundStyle(AppColor.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Text("Flipabulary is made by one person. A small tip keeps the app free, offline, and focused on learning. Thank you for helping the words keep coming.")
                .font(AppFont.body())
                .foregroundStyle(AppColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var options: some View {
        VStack(alignment: .leading, spacing: 14) {
            switch model.catalogState {
            case .loading:
                HStack(spacing: 10) {
                    ProgressView().tint(AppColor.accent)
                    Text("Loading App Store options…")
                        .font(AppFont.body())
                        .foregroundStyle(AppColor.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            case .unavailable(let message):
                InlineMessage(text: message, kind: .info)
            case .available:
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3),
                    spacing: 10
                ) {
                    ForEach(model.slots) { slot in
                        amountTile(slot)
                    }
                }

                if let message = model.message {
                    switch message {
                    case .success(let text): InlineMessage(text: text, kind: .success)
                    case .info(let text): InlineMessage(text: text, kind: .info)
                    case .failure(let text): InlineMessage(text: text, kind: .error)
                    }
                }

                PrimaryActionButton(
                    title: donateTitle,
                    systemImage: "heart",
                    isEnabled: model.canPurchase,
                    isWorking: model.isPurchasing
                ) {
                    Task { await model.purchase() }
                }
                .accessibilityIdentifier("support.donate")

                if dynamicTypeSize.isAccessibilitySize || UIDevice.current.userInterfaceIdiom == .phone {
                    finePrint
                }
            }
        }
    }

    private func amountTile(_ slot: SupportSlot) -> some View {
        let product = model.product(for: slot)
        let selected = model.selectedAmount == slot.amount
        return Button {
            model.select(amount: slot.amount)
        } label: {
            VStack(spacing: 5) {
                Text(LocalizedStringKey(slot.title))
                    .font(AppFont.font(14, .semibold))
                    .foregroundStyle(selected ? AppColor.onAccent : AppColor.textPrimary)
                Text(product?.displayPrice ?? "Unavailable")
                    .font(AppFont.font(12, .regular))
                    .foregroundStyle(selected ? AppColor.onAccent : AppColor.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 72)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(selected ? AppColor.accentStrong : AppColor.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(selected ? .clear : AppColor.divider, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(product == nil)
        .accessibilityLabel("\(slot.title), \(product?.displayPrice ?? "unavailable")")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("support.amount.\(slot.amount)")
    }

    private var donateTitle: String {
        if let product = model.selectedProduct {
            return "Donate \(product.displayPrice)"
        }
        return "Choose an amount"
    }

    private var finePrint: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Purchases are handled by the App Store. Tips are voluntary, repeatable, and unlock no features. One-time tips are not restorable.")
                .font(AppFont.caption())
                .foregroundStyle(AppColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Learning, widgets, and reminders work without any purchase.")
                .font(AppFont.caption())
                .foregroundStyle(AppColor.textMuted)
        }
    }
}

#Preview {
    SupportView(purchasing: PreviewSupportService())
        .environment(AppEnvironment(bootstrap: PersistenceContainer.make()!))
}
