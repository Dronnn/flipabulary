import SwiftUI

struct LaunchOverlayView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    let onFinish: () -> Void

    var body: some View {
        ZStack {
            AppColor.page.ignoresSafeArea()

            VStack(spacing: 24) {
                Image("LaunchCard")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 150, height: 150)
                    .scaleEffect(appeared ? 1 : 0.96)
                    .rotation3DEffect(
                        .degrees(appeared ? 0 : -8),
                        axis: (x: 0, y: 1, z: 0),
                        perspective: 0.55
                    )

                VStack(spacing: 9) {
                    Text(verbatim: "Flipabulary")
                        .font(AppFont.font(30, .semibold, relativeTo: .title))
                        .foregroundStyle(AppColor.textPrimary)
                        .offset(y: appeared ? 0 : 4)
                        .opacity(appeared ? 1 : 0.9)

                    Capsule()
                        .fill(AppColor.accent)
                        .frame(width: appeared ? 44 : 0, height: 3)
                        .opacity(appeared ? 1 : 0)
                }
            }
        }
        .accessibilityHidden(true)
        .task {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-DebugHoldLaunchOverlay") {
                appeared = true
                return
            }
            #endif
            if reduceMotion {
                withAnimation(.easeOut(duration: 0.2)) {
                    appeared = true
                }
                try? await Task.sleep(for: .milliseconds(450))
            } else {
                withAnimation(.spring(response: 0.6, dampingFraction: 0.78)) {
                    appeared = true
                }
                try? await Task.sleep(for: .milliseconds(950))
            }
            guard !Task.isCancelled else { return }
            onFinish()
        }
    }
}
