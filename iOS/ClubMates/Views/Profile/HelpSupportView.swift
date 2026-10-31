import SwiftUI

struct HelpSupportView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var expandedFAQ: String? = nil

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.background.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        heroBanner
                        contactCard
                        sectionLabel("Frequently Asked Questions")
                        ForEach(faqs) { faq in
                            faqCard(faq)
                        }
                        sectionLabel("Safety")
                        ForEach(safetyFAQs) { faq in
                            faqCard(faq)
                        }
                    }
                    .padding(.top, 20)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("Help & Support")
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
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(AppTheme.primaryGradient)

            Text("We're here to help")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(AppTheme.textPrimary)

            Text("Find answers to common questions below, or reach out to our support team directly.")
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

    // MARK: - Contact

    private var contactCard: some View {
        VStack(spacing: 10) {
            contactRow(
                icon: "envelope.fill",
                color: AppTheme.purple,
                title: "Email Support",
                subtitle: "support@clubmates.app",
                action: { openURL("mailto:support@clubmates.app") }
            )
            Divider().background(Color.white.opacity(0.06)).padding(.leading, 60)
            contactRow(
                icon: "ant.fill",
                color: AppTheme.pink,
                title: "Report a Bug",
                subtitle: "bugs@clubmates.app",
                action: { openURL("mailto:bugs@clubmates.app") }
            )
        }
        .background(AppTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.06), lineWidth: 1))
        .padding(.horizontal, 20)
    }

    private func contactRow(icon: String, color: Color, title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
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
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(AppTheme.textTertiary)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
        }
        .buttonStyle(.plain)
    }

    // MARK: - FAQ Card

    private func faqCard(_ faq: FAQ) -> some View {
        let isExpanded = expandedFAQ == faq.id

        return VStack(spacing: 0) {
            Button(action: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    expandedFAQ = isExpanded ? nil : faq.id
                }
            }) {
                HStack(spacing: 12) {
                    Text(faq.question)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(AppTheme.textPrimary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(AppTheme.textTertiary)
                }
                .padding(16)
            }
            .buttonStyle(.plain)

            if isExpanded {
                Divider()
                    .background(Color.white.opacity(0.06))
                    .padding(.horizontal, 16)

                Text(faq.answer)
                    .font(.system(size: 13, design: .rounded))
                    .foregroundColor(AppTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            }
        }
        .background(AppTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.06), lineWidth: 1))
        .padding(.horizontal, 20)
    }

    // MARK: - Section Label

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundColor(AppTheme.textTertiary)
            .textCase(.uppercase)
            .tracking(0.8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 4)
    }

    // MARK: - Helpers

    private func openURL(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        UIApplication.shared.open(url)
    }

    // MARK: - Data

    private struct FAQ: Identifiable {
        let id: String
        let question: String
        let answer: String
    }

    private var faqs: [FAQ] {[
        FAQ(id: "checkin", question: "How do I check in to a venue?",
            answer: "Tap a venue on the Discover tab. You must be physically within the venue's radius (usually 200m) for the check-in to succeed. ClubMates uses your GPS to verify this."),
        FAQ(id: "discover", question: "Why can't I see anyone on the discover feed?",
            answer: "You need to be checked in to a venue to see other people. If you're checked in and still see nothing, try adjusting your Dating Preferences — your age or height filters may be too narrow, or 'Verified Only' may be on."),
        FAQ(id: "match", question: "How do matches work?",
            answer: "When two people both like each other at the same venue, it's a match. You can then chat in the Matches tab. Matches are tied to the venue — you'll see where you first matched."),
        FAQ(id: "invite", question: "What is an Invite?",
            answer: "An Invite lets you choose a fixed treat and show intent without sending a message or payment. Chat unlocks only if the other person accepts the match."),
        FAQ(id: "undo", question: "Can I undo a swipe?",
            answer: "Yes — tap the undo button in the discover toolbar immediately after swiping. You can only undo the most recent swipe."),
        FAQ(id: "checkout", question: "What happens when I leave a venue?",
            answer: "You are automatically checked out when you move beyond the venue radius. Your profile is no longer visible in the discover feed, but your matches and messages remain."),
        FAQ(id: "delete", question: "How do I delete my account?",
            answer: "Go to Profile → scroll to the bottom → tap Delete Account. Your account is deactivated immediately and permanently deleted after 24 hours. You can cancel by logging back in within that window."),
    ]}

    private var safetyFAQs: [FAQ] {[
        FAQ(id: "block", question: "How do I block someone?",
            answer: "Open the person's profile from Matches or the Discover roster, tap the shield icon, and select Block. They will no longer appear in your discover feed and cannot see your profile."),
        FAQ(id: "report", question: "How do I report inappropriate behaviour?",
            answer: "Tap the shield icon on any profile and select Report. Choose a category, add details if needed, and submit. Our team reviews all reports within 24 hours."),
        FAQ(id: "sos", question: "What is the SOS feature?",
            answer: "If you feel unsafe, tap the SOS button in the app. It sends your current location and venue to our safety team and displays local emergency contacts. Your safety is our top priority."),
        FAQ(id: "verified", question: "What does the verified badge mean?",
            answer: "A blue checkmark means the person has completed selfie verification — a live photo was compared to their profile photos to confirm they are a real person. Verified profiles are more trustworthy."),
    ]}
}
