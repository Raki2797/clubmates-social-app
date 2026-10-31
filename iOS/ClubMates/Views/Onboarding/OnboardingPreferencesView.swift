import SwiftUI

struct OnboardingPreferencesView: View {
    @Binding var draft: UserProfile
    let onBack: () -> Void
    let onFinish: () -> Void

    var body: some View {
        ZStack(alignment: .bottom) {
            AppTheme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                // MARK: Header
                headerBar
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 12)

                // MARK: Scroll Content
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 28) {
                        introCard
                        lookingForSection
                        ageRangeSection
                        heightRangeSection
                        genderSection
                        verifiedOnlyRow
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                    .padding(.bottom, 120)
                }
            }

            // MARK: Bottom Bar
            bottomBar
        }
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack(alignment: .center) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(AppTheme.textPrimary)
                    .frame(width: 42, height: 42)
                    .background(AppTheme.surface)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)

            Spacer()

            VStack(spacing: 4) {
                Text("ClubMates")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(AppTheme.textPrimary)
                Text("Step 3 of 3")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(AppTheme.textSecondary)
            }

            Spacer()

            HStack(spacing: 4) {
                ForEach(0..<3) { _ in
                    Capsule()
                        .fill(AnyShapeStyle(AppTheme.primaryGradient))
                        .frame(width: 16, height: 6)
                }
            }
            .frame(width: 42, alignment: .trailing)
        }
    }

    // MARK: - Intro Card

    private var introCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(AppTheme.primaryGradient)
                    .frame(width: 56, height: 56)
                Image(systemName: "heart.fill")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundColor(.white)
            }

            Text("Your Preferences")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(AppTheme.textPrimary)

            Text("Tell us who you're looking for. This helps us show you the right people at venues.")
                .font(.system(size: 14, design: .rounded))
                .foregroundColor(AppTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(AppTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous))
    }

    // MARK: - Looking For

    private var lookingForSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    prefIcon("heart.fill")
                    Text("Looking For")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundColor(AppTheme.textPrimary)
                }

                FlowLayout(spacing: 8) {
                    ForEach(EditProfileView.lookingForOptions, id: \.self) { option in
                        let isSelected = draft.lookingFor == option
                        Button(action: { draft.lookingFor = isSelected ? "" : option }) {
                            Text(option)
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundColor(isSelected ? .white : AppTheme.textSecondary)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(isSelected ? AnyShapeStyle(AppTheme.primaryGradient) : AnyShapeStyle(AppTheme.surface))
                                .clipShape(Capsule())
                                .overlay(Capsule().stroke(isSelected ? Color.clear : AppTheme.pink.opacity(0.2), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(AppTheme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(AppTheme.pink.opacity(0.12), lineWidth: 1))

            if draft.lookingFor.isEmpty {
                Text("Select one to continue.")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundColor(AppTheme.pink.opacity(0.8))
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }

    // MARK: - Age Range

    private var ageRangeSection: some View {
        VStack(spacing: 14) {
            HStack(spacing: 10) {
                prefIcon("birthday.cake.fill")
                Text("Age Range")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(AppTheme.textPrimary)
                Spacer()
                Text("\(draft.preferences.ageMin) – \(draft.preferences.ageMax)")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.primaryGradient)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(AppTheme.pink.opacity(0.1))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(AppTheme.pink.opacity(0.25), lineWidth: 1))
            }

            HStack(spacing: 10) {
                Text("Min")
                    .font(.system(size: 13, design: .rounded))
                    .foregroundColor(AppTheme.textSecondary)
                    .frame(width: 28, alignment: .leading)
                Slider(
                    value: Binding(
                        get: { Double(draft.preferences.ageMin) },
                        set: {
                            draft.preferences.ageMin = min(max(18, Int($0)), draft.preferences.ageMax - 1)
                        }
                    ),
                    in: 18...55,
                    step: 1
                )
                .tint(AppTheme.pink)
            }

            HStack(spacing: 10) {
                Text("Max")
                    .font(.system(size: 13, design: .rounded))
                    .foregroundColor(AppTheme.textSecondary)
                    .frame(width: 28, alignment: .leading)
                Slider(
                    value: Binding(
                        get: { Double(draft.preferences.ageMax) },
                        set: {
                            draft.preferences.ageMax = max(min(60, Int($0)), draft.preferences.ageMin + 1)
                        }
                    ),
                    in: Double(draft.preferences.ageMin + 1)...60,
                    step: 1
                )
                .tint(AppTheme.pink)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(AppTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(AppTheme.pink.opacity(0.12), lineWidth: 1))
    }

    // MARK: - Height Range

    private var heightRangeSection: some View {
        VStack(spacing: 14) {
            HStack(spacing: 10) {
                prefIcon("ruler.fill")
                Text("Height Range")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(AppTheme.textPrimary)
                Spacer()
                Text("\(draft.preferences.heightMin) – \(draft.preferences.heightMax) cm")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.primaryGradient)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(AppTheme.pink.opacity(0.1))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(AppTheme.pink.opacity(0.25), lineWidth: 1))
            }

            HStack(spacing: 10) {
                Text("Min")
                    .font(.system(size: 13, design: .rounded))
                    .foregroundColor(AppTheme.textSecondary)
                    .frame(width: 28, alignment: .leading)
                Slider(
                    value: Binding(
                        get: { Double(draft.preferences.heightMin) },
                        set: {
                            draft.preferences.heightMin = min(max(140, Int($0)), draft.preferences.heightMax - 1)
                        }
                    ),
                    in: 140...210,
                    step: 1
                )
                .tint(AppTheme.pink)
            }

            HStack(spacing: 10) {
                Text("Max")
                    .font(.system(size: 13, design: .rounded))
                    .foregroundColor(AppTheme.textSecondary)
                    .frame(width: 28, alignment: .leading)
                Slider(
                    value: Binding(
                        get: { Double(draft.preferences.heightMax) },
                        set: {
                            draft.preferences.heightMax = max(min(220, Int($0)), draft.preferences.heightMin + 1)
                        }
                    ),
                    in: Double(draft.preferences.heightMin + 1)...220,
                    step: 1
                )
                .tint(AppTheme.pink)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(AppTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(AppTheme.pink.opacity(0.12), lineWidth: 1))
    }

    // MARK: - Gender (Show Me)

    private var genderSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                prefIcon("person.fill")
                Text("Show Me")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(AppTheme.textPrimary)
            }

            FlowLayout(spacing: 8) {
                ForEach(["Men", "Women", "Everyone"], id: \.self) { label in
                    let isSelected: Bool = {
                        switch label {
                        case "Everyone": return draft.preferences.genders.isEmpty
                        case "Men":      return draft.preferences.genders.contains("Male")
                        case "Women":    return draft.preferences.genders.contains("Female")
                        default:         return false
                        }
                    }()

                    Button(action: { toggleGender(label) }) {
                        Text(label)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundColor(isSelected ? .white : AppTheme.textSecondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(isSelected ? AnyShapeStyle(AppTheme.primaryGradient) : AnyShapeStyle(AppTheme.surface))
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(isSelected ? Color.clear : AppTheme.pink.opacity(0.2), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(AppTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(AppTheme.pink.opacity(0.12), lineWidth: 1))
    }

    // MARK: - Verified Only

    private var verifiedOnlyRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                prefIcon("checkmark.shield.fill")

                Text("Show Verified Only")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(AppTheme.textPrimary)

                Spacer()

                Toggle("", isOn: $draft.preferences.verifiedOnly)
                    .tint(AppTheme.pink)
                    .labelsHidden()
            }

            Text("Only show people with a verified selfie badge.")
                .font(.system(size: 12, design: .rounded))
                .foregroundColor(AppTheme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(AppTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(AppTheme.pink.opacity(0.12), lineWidth: 1))
        .padding(.horizontal, 0)
    }

    // MARK: - Bottom Bar

    private var canFinish: Bool {
        !draft.lookingFor.isEmpty
    }

    private var bottomBar: some View {
        VStack(spacing: 0) {
            Divider()
                .background(AppTheme.surface)
            Button(action: { if canFinish { onFinish() } }) {
                Text("Let's Go 🎉")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(canFinish ? AnyShapeStyle(AppTheme.primaryGradient) : AnyShapeStyle(AppTheme.surface))
                    .clipShape(Capsule())
            }
            .disabled(!canFinish)
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 16)
        }
        .background(AppTheme.background)
    }

    // MARK: - Helpers

    private func prefIcon(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(AppTheme.primaryGradient)
            .frame(width: 30, height: 30)
            .background(AppTheme.pink.opacity(0.12))
            .clipShape(Circle())
    }

    private func toggleGender(_ label: String) {
        switch label {
        case "Everyone":
            draft.preferences.genders = []
        case "Men":
            if draft.preferences.genders.contains("Male") {
                draft.preferences.genders.removeAll { $0 == "Male" }
            } else {
                draft.preferences.genders.append("Male")
            }
        case "Women":
            if draft.preferences.genders.contains("Female") {
                draft.preferences.genders.removeAll { $0 == "Female" }
            } else {
                draft.preferences.genders.append("Female")
            }
        default:
            break
        }
    }
}
