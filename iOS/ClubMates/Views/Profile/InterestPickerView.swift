import SwiftUI

struct InterestPickerView: View {
    @Binding var selected: [String]
    @Environment(\.dismiss) private var dismiss

    private let maxInterests = 8

    private let allInterests: [(category: String, items: [String])] = [
        ("Creative", ["Photography", "Painting", "Drawing", "Ceramics", "Knitting", "Writing", "Illustration", "Design"]),
        ("Music", ["Vinyl", "Jazz", "Indie", "Concerts", "Karaoke", "Guitar", "Piano", "Hip-hop"]),
        ("Food & Drink", ["Cooking", "Baking", "Coffee", "Wine", "Brunch", "Sushi", "Farmers Markets", "Cocktails"]),
        ("Active", ["Yoga", "Running", "Hiking", "Surfing", "Climbing", "Tennis", "Cycling", "Swimming"]),
        ("Mind", ["Books", "Podcasts", "Film", "Travel", "Languages", "Chess", "History", "Science"]),
        ("Social", ["Stand-up", "Trivia", "Board Games", "Thrifting", "Art Galleries", "Concerts", "Darts", "Karaoke"]),
        ("Outdoors", ["Camping", "Dogs", "Gardening", "Stargazing", "Beach", "Road Trips", "Mountains", "Sailing"]),
        ("Tech & Gaming", ["Code", "Gaming", "Anime", "Crypto", "AI", "Robotics", "VR", "Podcasts"]),
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.background.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 28) {
                        // Selection count pill
                        HStack {
                            Spacer()
                            Text("\(selected.count)/\(maxInterests) selected")
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundColor(selected.count >= maxInterests ? AppTheme.pink : AppTheme.textSecondary)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 7)
                                .background(AppTheme.surface)
                                .clipShape(Capsule())
                        }
                        .padding(.horizontal, 20)

                        ForEach(allInterests, id: \.category) { group in
                            categorySection(group.category, items: group.items)
                        }
                    }
                    .padding(.top, 16)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("Interests")
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
        .presentationDetents([.large])
    }

    private func categorySection(_ title: String, items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(AppTheme.textSecondary)
                .textCase(.uppercase)
                .tracking(0.8)
                .padding(.horizontal, 20)

            FlowLayout(spacing: 10) {
                ForEach(items, id: \.self) { item in
                    interestChip(item)
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private func interestChip(_ item: String) -> some View {
        let isSelected = selected.contains(item)
        let isDisabled = !isSelected && selected.count >= maxInterests

        return Button(action: {
            guard !isDisabled else { return }
            if isSelected {
                selected.removeAll { $0 == item }
            } else {
                selected.append(item)
            }
        }) {
            Text(item)
                .font(.system(size: 14, weight: isSelected ? .semibold : .medium, design: .rounded))
                .foregroundColor(isSelected ? .white : (isDisabled ? AppTheme.textTertiary : AppTheme.textPrimary))
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .background(
                    Group {
                        if isSelected {
                            AnyView(AppTheme.primaryGradient)
                        } else {
                            AnyView(AppTheme.surface.opacity(isDisabled ? 0.5 : 1))
                        }
                    }
                )
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(isSelected ? Color.clear : AppTheme.textTertiary.opacity(0.2), lineWidth: 1)
                )
                .scaleEffect(isSelected ? 1.03 : 1)
                .animation(.spring(response: 0.25, dampingFraction: 0.6), value: isSelected)
        }
        .disabled(isDisabled)
    }
}
