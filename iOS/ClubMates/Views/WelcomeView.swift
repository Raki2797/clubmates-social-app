import SwiftUI

struct WelcomeView: View {
    @State private var authIntent: AuthIntent? = nil

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.background.ignoresSafeArea()

                backgroundOrbs

                VStack(spacing: 0) {
                    Spacer()

                    brandSection

                    Spacer()

                    ctaSection
                        .padding(.horizontal, 24)
                        .padding(.bottom, 48)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(item: $authIntent) { intent in
                AuthenticationFlowView(intent: intent)
            }
        }
    }

    private var backgroundOrbs: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color(hex: "C44EFF").opacity(0.25), .clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 200
                    )
                )
                .frame(width: 400, height: 400)
                .offset(x: -100, y: -220)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color(hex: "FF6B9D").opacity(0.2), .clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 180
                    )
                )
                .frame(width: 360, height: 360)
                .offset(x: 140, y: 160)
        }
    }

    private var brandSection: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: "FF6B9D"), Color(hex: "C44EFF")],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 88, height: 88)

                Image(systemName: "heart.fill")
                    .font(.system(size: 40, weight: .bold))
                    .foregroundColor(.white)
            }

            VStack(spacing: 8) {
                Text("ClubMates")
                    .font(.system(size: 38, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.primaryGradient)

                Text("Meet people at the same venues.\nSwipe, match, and connect.")
                    .font(.system(size: 16, design: .rounded))
                    .foregroundColor(AppTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }
        }
    }

    private var ctaSection: some View {
        VStack(spacing: 14) {
            Button {
                authIntent = .createAccount
            } label: {
                Text("Create Account")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 17)
                    .background(AppTheme.primaryGradient)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
            .buttonStyle(.plain)

            Button {
                authIntent = .login
            } label: {
                Text("Log In")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundColor(AppTheme.textPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 17)
                    .background(AppTheme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(AppTheme.surface, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)

            Text("By continuing you agree to our Terms & Privacy Policy.")
                .font(.system(size: 12, design: .rounded))
                .foregroundColor(AppTheme.textTertiary)
                .multilineTextAlignment(.center)
                .padding(.top, 4)
        }
    }
}
