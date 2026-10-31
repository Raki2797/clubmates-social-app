import SwiftUI

struct PreferencesView: View {
    @Binding var preferences: DatePreferences
    @Binding var lookingFor: String
    @Binding var isGhostMode: Bool
    @Environment(\.dismiss) private var dismiss

    private let lookingForOptions = ["Dating", "Something Casual", "Friendship", "Open to Anything"]
    private let genderOptions = ["Men", "Women", "Non-binary"]

    var body: some View {
        NavigationStack {
            ZStack {
                preferenceBackground.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        heroHeader
                        lookingForSection
                        ageRangeSection
                        heightRangeSection
                        genderSection
                        verifiedOnlySection
                        ghostModeSection
                    }
                    .padding(.top, 12)
                    .padding(.bottom, 40)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    // MARK: - Header

    private var preferenceBackground: some View {
        ZStack {
            AppTheme.background
            LinearGradient(
                colors: [
                    AppTheme.surface.opacity(0.55),
                    AppTheme.background,
                    AppTheme.cardBackground.opacity(0.65)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private var heroHeader: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Dating Preferences")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundColor(AppTheme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("Tune who appears in your discover feed.")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundColor(AppTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 12)

                Button(action: { dismiss() }) {
                    Text("Done")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .frame(height: 42)
                        .background(AppTheme.primaryGradient)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }

            FlowLayout(spacing: 8) {
                summaryPill(icon: "heart.fill", text: Self.lookingForSummary(lookingFor))
                summaryPill(icon: "birthday.cake.fill", text: "\(preferences.ageMin)-\(preferences.ageMax)")
                summaryPill(icon: "ruler.fill", text: "\(preferences.heightMin)-\(preferences.heightMax) cm")
                summaryPill(icon: "person.2.fill", text: Self.genderSummary(preferences.genders))
            }
        }
        .padding(20)
        .background(
            LinearGradient(
                colors: [
                    AppTheme.cardBackground,
                    AppTheme.surface.opacity(0.82)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(AppTheme.pink.opacity(0.16), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.28), radius: 20, x: 0, y: 12)
        .padding(.horizontal, 16)
    }

    private func summaryPill(icon: String, text: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(AppTheme.primaryGradient)

            Text(text)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(AppTheme.textPrimary)
                .lineLimit(1)
        }
        .padding(.horizontal, 11)
        .frame(height: 32)
        .background(AppTheme.background.opacity(0.62))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(AppTheme.surfaceElevated.opacity(0.75), lineWidth: 1))
    }

    // MARK: - Looking For

    private var lookingForSection: some View {
        prefCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    prefIcon("heart.fill")
                    Text("Looking For")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundColor(AppTheme.textPrimary)
                }
                FlowLayout(spacing: 8) {
                    ForEach(lookingForOptions, id: \.self) { option in
                        let isSelected = lookingFor == option
                        Button(action: { lookingFor = isSelected ? "" : option }) {
                            Text(option)
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundColor(isSelected ? .white : AppTheme.textSecondary)
                                .padding(.horizontal, 14).padding(.vertical, 8)
                                .background(isSelected ? AnyShapeStyle(AppTheme.primaryGradient) : AnyShapeStyle(AppTheme.surface))
                                .clipShape(Capsule())
                                .overlay(Capsule().stroke(isSelected ? Color.clear : AppTheme.pink.opacity(0.2), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Age Range

    private var ageRangeSection: some View {
        prefCard {
            VStack(spacing: 14) {
                HStack {
                    prefIcon("birthday.cake.fill")
                    Text("Age Range")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundColor(AppTheme.textPrimary)
                    Spacer()
                    Text("\(preferences.ageMin) – \(preferences.ageMax)")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.primaryGradient)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(AppTheme.pink.opacity(0.1))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(AppTheme.pink.opacity(0.25), lineWidth: 1))
                }

                    RangeSlider(
                        low: Binding(
                            get: { Double(preferences.ageMin) },
                            set: {
                                preferences.ageMin = Self.clampedLowerRangeValue(
                                    Int($0),
                                    upper: preferences.ageMax,
                                    bounds: 18...60
                                )
                            }
                        ),
                        high: Binding(
                            get: { Double(preferences.ageMax) },
                            set: {
                                preferences.ageMax = Self.clampedUpperRangeValue(
                                    Int($0),
                                    lower: preferences.ageMin,
                                    bounds: 18...60
                                )
                            }
                        ),
                        range: 18...60,
                        step: 1
                )

                HStack {
                    Text("18")
                    Spacer()
                    Text("60")
                }
                .font(.system(size: 11, design: .rounded))
                .foregroundColor(AppTheme.textTertiary)
            }
        }
    }

    // MARK: - Height Range

    private var heightRangeSection: some View {
        prefCard {
            VStack(spacing: 14) {
                HStack {
                    prefIcon("ruler.fill")
                    Text("Height Range")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundColor(AppTheme.textPrimary)
                    Spacer()
                    Text("\(preferences.heightMin) – \(preferences.heightMax) cm")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.primaryGradient)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(AppTheme.pink.opacity(0.1))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(AppTheme.pink.opacity(0.25), lineWidth: 1))
                }

                    RangeSlider(
                        low: Binding(
                            get: { Double(preferences.heightMin) },
                            set: {
                                preferences.heightMin = Self.clampedLowerRangeValue(
                                    Int($0),
                                    upper: preferences.heightMax,
                                    bounds: 140...220
                                )
                            }
                        ),
                        high: Binding(
                            get: { Double(preferences.heightMax) },
                            set: {
                                preferences.heightMax = Self.clampedUpperRangeValue(
                                    Int($0),
                                    lower: preferences.heightMin,
                                    bounds: 140...220
                                )
                            }
                        ),
                        range: 140...220,
                        step: 1
                )

                HStack {
                    Text("140 cm")
                    Spacer()
                    Text("220 cm")
                }
                .font(.system(size: 11, design: .rounded))
                .foregroundColor(AppTheme.textTertiary)
            }
        }
    }

    // MARK: - Gender Preference

    private var genderSection: some View {
        prefCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    prefIcon("person.2.fill")
                    Text("Show Me")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundColor(AppTheme.textPrimary)
                    Spacer()
                }

                FlowLayout(spacing: 10) {
                    ForEach(genderOptions, id: \.self) { option in
                        genderChip(option)
                    }
                    genderChip("Everyone")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func genderChip(_ label: String) -> some View {
        let isEveryone = label == "Everyone"
        let isSelected = isEveryone
            ? preferences.genders.isEmpty
            : preferences.genders.contains(label)

        return Button(action: { toggleGender(label) }) {
            Text(label)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(isSelected ? .white : AppTheme.textSecondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(isSelected ? AnyView(AppTheme.primaryGradient) : AnyView(AppTheme.surface))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(isSelected ? Color.clear : AppTheme.pink.opacity(0.2), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func toggleGender(_ label: String) {
        preferences.genders = Self.toggledGenderSelection(current: preferences.genders, label: label)
    }

    // MARK: - Verified Only

    private var verifiedOnlySection: some View {
        prefCard {
            HStack(spacing: 12) {
                prefIcon("checkmark.seal.fill")
                VStack(alignment: .leading, spacing: 2) {
                    Text("Verified Profiles Only")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundColor(AppTheme.textPrimary)
                    Text("Only show selfie-verified users")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundColor(AppTheme.textSecondary)
                }
                Spacer()
                Toggle("", isOn: $preferences.verifiedOnly)
                    .tint(AppTheme.pink)
                    .labelsHidden()
            }
        }
    }

    // MARK: - Ghost Mode

    private var ghostModeSection: some View {
        prefCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    Image(systemName: isGhostMode ? "eye.slash.fill" : "eye.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(isGhostMode ? AnyShapeStyle(AppTheme.primaryGradient) : AnyShapeStyle(AppTheme.textSecondary))
                        .frame(width: 30, height: 30)
                        .background((isGhostMode ? AppTheme.pink : AppTheme.surface).opacity(0.18))
                        .clipShape(Circle())

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Ghost Mode")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundColor(AppTheme.textPrimary)
                        Text(isGhostMode ? "Hidden from venue discovery" : "Visible when checked in")
                            .font(.system(size: 12, design: .rounded))
                            .foregroundColor(AppTheme.textSecondary)
                    }

                    Spacer()

                    Toggle("", isOn: $isGhostMode)
                        .tint(AppTheme.pink)
                        .labelsHidden()
                }

                Text("When on, people at the same venue won't see you in discovery. Your existing matches and chats still work.")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundColor(AppTheme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Helpers

    private func prefCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(AppTheme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppTheme.pink.opacity(0.12), lineWidth: 1))
            .padding(.horizontal, Self.preferenceCardHorizontalPadding)
    }

    private func prefIcon(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(AppTheme.primaryGradient)
            .frame(width: 30, height: 30)
            .background(AppTheme.pink.opacity(0.12))
            .clipShape(Circle())
    }
}

extension PreferencesView {
    static let preferenceCardHorizontalPadding: CGFloat = 20

    static func lookingForSummary(_ lookingFor: String) -> String {
        lookingFor.isEmpty ? "Open" : lookingFor
    }

    static func genderSummary(_ genders: [String]) -> String {
        genders.isEmpty ? "Everyone" : genders.joined(separator: ", ")
    }

    static func toggledGenderSelection(current: [String], label: String) -> [String] {
        guard label != "Everyone" else { return [] }

        if current.contains(label) {
            return current.filter { $0 != label }
        }

        return current + [label]
    }

    static func clampedLowerRangeValue(_ value: Int, upper: Int, bounds: ClosedRange<Int>) -> Int {
        min(max(bounds.lowerBound, value), upper - 1)
    }

    static func clampedUpperRangeValue(_ value: Int, lower: Int, bounds: ClosedRange<Int>) -> Int {
        max(min(bounds.upperBound, value), lower + 1)
    }
}

// MARK: - Range Slider

private struct RangeSlider: View {
    @Binding var low: Double
    @Binding var high: Double
    let range: ClosedRange<Double>
    let step: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                // Track background
                Capsule()
                    .fill(AppTheme.surface)
                    .frame(height: 4)

                // Active range
                Capsule()
                    .fill(AppTheme.primaryGradient)
                    .frame(
                        width: thumbX(high, geo) - thumbX(low, geo),
                        height: 4
                    )
                    .offset(x: thumbX(low, geo))

                // Low thumb
                Circle()
                    .fill(Color.white)
                    .frame(width: 22, height: 22)
                    .shadow(color: .black.opacity(0.25), radius: 4, x: 0, y: 2)
                    .overlay(Circle().stroke(AppTheme.pink.opacity(0.5), lineWidth: 1.5))
                    .offset(x: thumbX(low, geo) - 11)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                let newVal = valueFromX(value.location.x, geo)
                                low = min(max(range.lowerBound, snap(newVal)), high - step)
                            }
                    )

                // High thumb
                Circle()
                    .fill(Color.white)
                    .frame(width: 22, height: 22)
                    .shadow(color: .black.opacity(0.25), radius: 4, x: 0, y: 2)
                    .overlay(Circle().stroke(AppTheme.pink.opacity(0.5), lineWidth: 1.5))
                    .offset(x: thumbX(high, geo) - 11)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                let newVal = valueFromX(value.location.x, geo)
                                high = max(min(range.upperBound, snap(newVal)), low + step)
                            }
                    )
            }
        }
        .frame(height: 22)
    }

    private func thumbX(_ value: Double, _ geo: GeometryProxy) -> CGFloat {
        let pct = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
        return CGFloat(pct) * geo.size.width
    }

    private func valueFromX(_ x: CGFloat, _ geo: GeometryProxy) -> Double {
        let pct = Double(max(0, min(x, geo.size.width)) / geo.size.width)
        return range.lowerBound + pct * (range.upperBound - range.lowerBound)
    }

    private func snap(_ value: Double) -> Double {
        (value / step).rounded() * step
    }
}
