import SwiftUI

struct MatchAlertView: View {
    let profile: UserProfile
    let onKeepSwiping: () -> Void
    let onSendMessage: () -> Void

    @State private var appeared = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.85)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // Animated title
                VStack(spacing: 8) {
                    Text("It's a")
                        .font(.system(size: 22, weight: .light, design: .rounded))
                        .foregroundColor(.white.opacity(0.8))
                    Text("Match!")
                        .font(.system(size: 52, weight: .black, design: .rounded))
                        .foregroundStyle(AppTheme.primaryGradient)
                }
                .scaleEffect(appeared ? 1 : 0.5)
                .opacity(appeared ? 1 : 0)
                .padding(.bottom, 40)

                // Avatars
                HStack(spacing: -20) {
                    AvatarPlaceholder(name: "A", size: 110)
                        .overlay(Circle().stroke(Color.white, lineWidth: 3))
                        .offset(x: appeared ? 0 : -60)
                        .opacity(appeared ? 1 : 0)

                    Image(systemName: "heart.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(AppTheme.primaryGradient)
                        .background(Circle().fill(AppTheme.background).padding(-8))
                        .zIndex(1)
                        .scaleEffect(appeared ? 1 : 0)

                    ProfileAvatar(profile: profile, size: 110)
                        .overlay(Circle().stroke(Color.white, lineWidth: 3))
                        .offset(x: appeared ? 0 : 60)
                        .opacity(appeared ? 1 : 0)
                }
                .padding(.bottom, 24)

                Text("You and \(profile.name) liked each other")
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundColor(AppTheme.textSecondary)
                    .opacity(appeared ? 1 : 0)
                    .padding(.bottom, 48)

                // Buttons
                VStack(spacing: 14) {
                    Button(action: onSendMessage) {
                        HStack {
                            Image(systemName: "paperplane.fill")
                            Text("Send a message")
                        }
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(AppTheme.primaryGradient)
                        .clipShape(Capsule())
                    }

                    Button(action: onKeepSwiping) {
                        Text("Keep swiping")
                            .font(.system(size: 17, weight: .medium, design: .rounded))
                            .foregroundColor(AppTheme.textSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                            .background(AppTheme.surface)
                            .clipShape(Capsule())
                    }
                }
                .padding(.horizontal, 32)
                .opacity(appeared ? 1 : 0)

                Spacer()
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.1)) {
                appeared = true
            }
        }
    }
}
