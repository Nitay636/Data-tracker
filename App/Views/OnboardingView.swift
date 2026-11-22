import StoreKit
import SwiftUI

/// Shown on first launch and from Settings.
struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var page = 0

    private struct Page {
        let symbol: String
        let color: Color
        let title: String
        let text: String
    }

    private let pages = [
        Page(symbol: "chart.bar.fill", color: .wifiColor, title: "Your data usage",
             text: "Wi-Fi and cellular, by day, week or month."),
        Page(symbol: "square.grid.2x2.fill", color: .purple, title: "Usage per app",
             text: "See which apps use the most, and when."),
        Page(symbol: "lock.shield.fill", color: .cellularColor, title: "Private by design",
             text: "Per-app tracking uses a VPN that runs only on this iPhone. Nothing leaves it."),
        Page(symbol: "square.text.square.fill", color: .orange, title: "Widget",
             text: "Add DataTracker to your Home Screen to see today at a glance.")
    ]

    var body: some View {
        VStack(spacing: 24) {
            TabView(selection: $page) {
                ForEach(pages.indices, id: \.self) { index in
                    let item = pages[index]
                    VStack(spacing: 20) {
                        Image(systemName: item.symbol)
                            .font(.system(size: 64, weight: .semibold))
                            .foregroundStyle(item.color)
                            .frame(height: 90)
                        Text(item.title)
                            .font(.title.weight(.bold))
                        Text(item.text)
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            VStack(spacing: 12) {
                if page < pages.count - 1 {
                    Button {
                        withAnimation { page += 1 }
                    } label: {
                        Text("Continue").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    Button("Skip") { finish() }
                } else {
                    Button {
                        Task {
                            await model.vpn.turnOn()
                            model.reload()
                            finish()
                        }
                    } label: {
                        Group {
                            if model.vpn.isBusy {
                                ProgressView().tint(.white)
                            } else {
                                Text("Turn On Per-App Tracking")
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.vpn.isBusy)
                    Button("Not Now") { finish() }
                }
            }
            .controlSize(.large)
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
        .sensoryFeedback(.selection, trigger: page)
        .interactiveDismissDisabled()
    }

    private func finish() {
        model.finishOnboarding()
        dismiss()
    }
}

/// Shown once, after the user first looks at an app's usage.
struct RatingPromptView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.requestReview) private var requestReview

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Hello")
                        .font(.title.weight(.bold))
                    Text("My name is Nitay 🙃")
                        .font(.title3.weight(.semibold))
                    Text("I built this app for personal use, and thought that more people would love to use it.")
                    Text("If you enjoyed this app, I really appreciate to get a good review from you on the App Store.")
                    Text("This will help to more people to enjoy the app.")
                    Text("If you find some bugs or have ideas for new features and improvements, I would like to hear from you. You can contact me in the settings. I promise I’ll read it all. (And also give the appropriate credit in the updates on the store 😉)")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            VStack(spacing: 12) {
                Button {
                    dismiss()
                    // The system rating sheet lets the user tap stars right away.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { requestReview() }
                } label: {
                    Label("Rate DataTracker", systemImage: "star.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                Button("Not Now") { dismiss() }
            }
            .controlSize(.large)
        }
        .padding(24)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}
