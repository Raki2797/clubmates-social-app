import SwiftUI

struct NotificationSettingsView: View {
    @Binding var notifPrefs: NotificationPreferences
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.background.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        masterToggleCard
                        individualTogglesCard
                            .opacity(notifPrefs.enabled ? 1 : 0.4)
                            .disabled(!notifPrefs.enabled)
                    }
                    .padding(.top, 20)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("Notifications")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(AppTheme.cardBackground, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(AppTheme.primaryGradient)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                }
            }
        }
    }

    // MARK: - Master Toggle

    private var masterToggleCard: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(AppTheme.purple.opacity(0.15))
                    .frame(width: 42, height: 42)
                Image(systemName: notifPrefs.enabled ? "bell.fill" : "bell.slash.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(AppTheme.primaryGradient)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("Enable Notifications")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundColor(AppTheme.textPrimary)
                Text(notifPrefs.enabled ? "You'll receive push notifications" : "All notifications are turned off")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundColor(AppTheme.textSecondary)
            }

            Spacer()

            Toggle("", isOn: $notifPrefs.enabled)
                .tint(AppTheme.pink)
                .labelsHidden()
        }
        .padding(16)
        .background(AppTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppTheme.pink.opacity(0.18), lineWidth: 1))
        .padding(.horizontal, 20)
    }

    // MARK: - Individual Toggles

    private var individualTogglesCard: some View {
        VStack(spacing: 0) {
            notifRow(
                icon: "heart.fill",
                color: AppTheme.pink,
                title: "New Matches",
                subtitle: "When someone matches with you",
                isOn: $notifPrefs.newMatch
            )
            divider
            notifRow(
                icon: "bubble.fill",
                color: AppTheme.purple,
                title: "New Messages",
                subtitle: "When a match sends you a message",
                isOn: $notifPrefs.newMessage
            )
            divider
            notifRow(
                icon: "hand.thumbsup.fill",
                color: AppTheme.green,
                title: "Someone Liked You",
                subtitle: "When someone swipes right on you",
                isOn: $notifPrefs.likedYou
            )
            divider
            notifRow(
                icon: "star.fill",
                color: AppTheme.gold,
                title: "Invites",
                subtitle: "When someone sends you a treat invite",
                isOn: $notifPrefs.superLike
            )
            divider
            notifRow(
                icon: "location.fill",
                color: .blue,
                title: "Venue Activity",
                subtitle: "When a match checks in at your venue",
                isOn: $notifPrefs.venueActivity
            )
        }
        .background(AppTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.06), lineWidth: 1))
        .padding(.horizontal, 20)
    }

    private func notifRow(icon: String, color: Color, title: String, subtitle: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(color)
                .frame(width: 36, height: 36)
                .background(color.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundColor(AppTheme.textPrimary)
                Text(subtitle)
                    .font(.system(size: 12, design: .rounded))
                    .foregroundColor(AppTheme.textSecondary)
            }

            Spacer()

            Toggle("", isOn: isOn)
                .tint(AppTheme.pink)
                .labelsHidden()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    private var divider: some View {
        Divider()
            .background(Color.white.opacity(0.06))
            .padding(.leading, 68)
    }
}
