import SwiftUI

struct PrivacyView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var expandedSection: String? = nil

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.background.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        heroBanner
                        ForEach(sections) { section in
                            accordionCard(section: section)
                        }
                        footerNote
                    }
                    .padding(.top, 20)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("Privacy")
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

    // MARK: - Hero

    private var heroBanner: some View {
        VStack(spacing: 10) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 36, weight: .semibold))
                .foregroundStyle(AppTheme.primaryGradient)

            Text("Your privacy matters")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(AppTheme.textPrimary)

            Text("ClubMates is built on the principle that you control your data. We collect only what's needed to run the app, never sell it, and delete it permanently when you ask.")
                .font(.system(size: 13, design: .rounded))
                .foregroundColor(AppTheme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(AppTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(AppTheme.pink.opacity(0.15), lineWidth: 1))
        .padding(.horizontal, 20)
    }

    // MARK: - Accordion

    private func accordionCard(section: PolicySection) -> some View {
        let isExpanded = expandedSection == section.id

        return VStack(spacing: 0) {
            Button(action: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    expandedSection = isExpanded ? nil : section.id
                }
            }) {
                HStack(spacing: 14) {
                    Image(systemName: section.icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(section.color)
                        .frame(width: 36, height: 36)
                        .background(section.color.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 10))

                    Text(section.title)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundColor(AppTheme.textPrimary)

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(AppTheme.textTertiary)
                }
                .padding(16)
            }
            .buttonStyle(.plain)

            if isExpanded {
                Divider()
                    .background(Color.white.opacity(0.06))
                    .padding(.horizontal, 16)

                VStack(alignment: .leading, spacing: 10) {
                    ForEach(section.items, id: \.self) { item in
                        HStack(alignment: .top, spacing: 10) {
                            Circle()
                                .fill(section.color.opacity(0.7))
                                .frame(width: 5, height: 5)
                                .padding(.top, 6)
                            Text(item)
                                .font(.system(size: 13, design: .rounded))
                                .foregroundColor(AppTheme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(AppTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.06), lineWidth: 1))
        .padding(.horizontal, 20)
    }

    // MARK: - Footer

    private var footerNote: some View {
        VStack(spacing: 6) {
            Text("Last updated June 2025")
                .font(.system(size: 11, design: .rounded))
                .foregroundColor(AppTheme.textTertiary)
            Text("Questions? Contact us at privacy@clubmates.app")
                .font(.system(size: 11, design: .rounded))
                .foregroundColor(AppTheme.textTertiary)
        }
        .padding(.top, 8)
    }

    // MARK: - Data

    private struct PolicySection: Identifiable {
        let id: String
        let icon: String
        let color: Color
        let title: String
        let items: [String]
    }

    private var sections: [PolicySection] {
        [
            PolicySection(
                id: "collect",
                icon: "tray.fill",
                color: AppTheme.purple,
                title: "What We Collect",
                items: [
                    "Phone number — used for OTP login only, never shown on your profile.",
                    "Profile info — name, age, gender, height, profession, bio, interests, and prompts you provide.",
                    "Photos — profile photos and a one-time verification selfie stored securely in Supabase Storage.",
                    "Location — your GPS coordinates at check-in only, used to verify you are within a venue's radius. We do not track your location continuously.",
                    "Activity — swipes, matches, messages, and check-ins needed to run the app.",
                    "Device token — your push notification token (APNs) to deliver notifications you've enabled.",
                    "Session data — a short-lived access token (15 min) and refresh token (30 days) to keep you logged in."
                ]
            ),
            PolicySection(
                id: "use",
                icon: "gearshape.fill",
                color: AppTheme.green,
                title: "How We Use Your Data",
                items: [
                    "To match you with people at the same venue in real time.",
                    "To show your profile to other users checked in at the same venue.",
                    "To send push notifications for matches, messages, and likes — only for the types you've enabled.",
                    "To verify your identity via selfie comparison so the community stays authentic.",
                    "To enforce safety features like blocks, reports, and account deletion.",
                    "We never use your data for advertising or sell it to third parties."
                ]
            ),
            PolicySection(
                id: "store",
                icon: "externaldrive.fill",
                color: .blue,
                title: "How We Store It",
                items: [
                    "Profile data is stored in a PostgreSQL database hosted on Supabase (EU region).",
                    "Photos are stored in Supabase Storage with access-controlled signed URLs.",
                    "Session tokens are stored in Redis (Upstash) and expire automatically.",
                    "OTP codes are hashed before storage and deleted immediately after use.",
                    "All data is encrypted at rest and in transit over HTTPS/WSS."
                ]
            ),
            PolicySection(
                id: "share",
                icon: "person.2.fill",
                color: AppTheme.pink,
                title: "What Others Can See",
                items: [
                    "Other users at the same venue can see your name, age, photos, bio, prompts, interests, height, profession, and Looking For status.",
                    "Your phone number is never shown to other users.",
                    "Your exact GPS location is never shared — only your venue check-in is visible.",
                    "After you leave a venue or uncheck-in, you are no longer visible in the discover feed.",
                    "Ghost Mode hides you from venue rosters, discovery queues, and venue occupancy while it is enabled.",
                    "Blocked or reported users cannot see your profile."
                ]
            ),
            PolicySection(
                id: "retention",
                icon: "clock.fill",
                color: AppTheme.gold,
                title: "How Long We Keep It",
                items: [
                    "Your data is kept for as long as your account is active.",
                    "OTP verification codes are deleted immediately after a successful login.",
                    "Session tokens expire after 30 days of inactivity.",
                    "Check-in location coordinates are not stored after the check-in session ends.",
                    "When you delete your account, a 24-hour grace period begins — you can cancel deletion by logging back in.",
                    "After 24 hours, all your data is permanently deleted: profile, photos, matches, messages, swipes, and device tokens."
                ]
            ),
            PolicySection(
                id: "rights",
                icon: "hand.raised.fill",
                color: AppTheme.green,
                title: "Your Rights",
                items: [
                    "Access — you can view all your profile data directly in the app.",
                    "Edit — update or delete any part of your profile at any time.",
                    "Delete — delete your account from Profile → Settings. All data is permanently erased within 24 hours.",
                    "Notifications — manage exactly which notifications you receive from Profile → Notifications.",
                    "Discovery — use Ghost Mode to hide from venue discovery, or adjust your Dating Preferences to control who you see.",
                    "Block & Report — remove any user from your experience at any time."
                ]
            )
        ]
    }
}
