import SwiftUI

struct ProfileCardView: View {
    let profile: UserProfile
    @Binding var dragOffset: CGSize
    let likeOpacity: Double
    let nopeOpacity: Double
    let superLikeOpacity: Double
    var isTopCard: Bool = false
    var onDragChanged: ((DragGesture.Value) -> Void)? = nil
    var onDragEnded: ((DragGesture.Value) -> Void)? = nil

    @State private var selectedPhotoIndex = 0
    @State private var activeSection: ProfileSection = .details
    @State private var expandedPromptIDs: Set<UUID> = []
    @State private var hasAppeared = false

    private let accent = AppTheme.pink
    private let accentSecondary = AppTheme.purple
    private let cardBase = AppTheme.cardBackground
    private let inkPanel = AppTheme.surface.opacity(0.94)
    private let inkPanelRaised = AppTheme.surfaceElevated

    private enum ProfileSection: String, CaseIterable, Hashable {
        case details = "Info"
        case about = "About"
        case prompts = "Know Me"
        case photos = "Photos"
        case interests = "Interests"

        var icon: String {
            switch self {
            case .details:
                return "person.text.rectangle.fill"
            case .about:
                return "quote.opening"
            case .prompts:
                return "text.bubble.fill"
            case .photos:
                return "photo.stack.fill"
            case .interests:
                return "heart.text.square.fill"
            }
        }
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                cardScroll(geo: geo)
                swipeBadges
            }
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius))
            .shadow(color: .black.opacity(0.5), radius: 24, x: 0, y: 12)
            .rotationEffect(.degrees(isTopCard ? Double(dragOffset.width / 22) : 0))
            .offset(isTopCard ? dragOffset : .zero)
            .gesture(isTopCard ? dragGesture : nil)
        }
    }

    // MARK: - Scrollable Card Content

    private func cardScroll(geo: GeometryProxy) -> some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    photoHeader(geo: geo)

                    floatingSectionNav(proxy: proxy)
                        .padding(.horizontal, 16)
                        .padding(.top, -20)

                    infoPanel
                }
            }
            .background(profileBackdrop)
            .coordinateSpace(name: "profileCardScroll")
            .onAppear {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.78)) {
                    hasAppeared = true
                }
            }
        }
    }

    // MARK: - Hero Photo Header

    private func photoHeader(geo: GeometryProxy) -> some View {
        let h = AppTheme.heroPhotoHeight
        let photos = profile.photos.isEmpty ? [ProfilePhoto(systemName: "person.fill")] : profile.photos

        return GeometryReader { headerProxy in
            let offsetY = headerProxy.frame(in: .named("profileCardScroll")).minY

            ZStack(alignment: .bottom) {
                TabView(selection: $selectedPhotoIndex) {
                    ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                        ProfilePhotoView(
                            photo: photo,
                            symbolName: "person.fill",
                            symbolSize: 110,
                            gradientColors: profileGradientColors,
                            symbolOpacity: 0.12
                        )
                        .frame(width: geo.size.width, height: h)
                        .scaleEffect(offsetY > 0 ? 1 + min(offsetY / 900, 0.08) : 1)
                        .offset(y: offsetY > 0 ? -offsetY * 0.18 : offsetY * 0.12)
                        .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(width: geo.size.width, height: h)

                LinearGradient(
                    colors: [
                        .black.opacity(0.08),
                        .clear,
                        .black.opacity(0.88)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: h)

                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 6) {
                        ForEach(photos.indices, id: \.self) { index in
                            Capsule()
                                .fill(index == selectedPhotoIndex ? accent : Color.white.opacity(0.28))
                                .frame(width: index == selectedPhotoIndex ? 36 : 26, height: 3)
                                .animation(.spring(response: 0.28, dampingFraction: 0.78), value: selectedPhotoIndex)
                        }

                        Spacer()

                        Text("Photo \(selectedPhotoIndex + 1)")
                            .font(.system(size: 11, weight: .black, design: .rounded))
                            .foregroundColor(.white.opacity(0.92))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.black.opacity(0.46))
                            .clipShape(Capsule())
                    }
                    glassIdentityOverlay
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 18)
            }
        }
        .frame(height: h)
        .frame(maxWidth: .infinity)
    }

    private var glassIdentityOverlay: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(profile.name)
                    .font(.system(size: 38, weight: .regular, design: .serif))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                Text("\(profile.age)")
                    .font(.system(size: 25, weight: .regular, design: .serif))
                    .foregroundStyle(AppTheme.primaryGradient)

                if profile.isVerified {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(AppTheme.primaryGradient)
                        .font(.system(size: 18))
                }
            }

            HStack(spacing: 8) {
                if let profession = cleanProfession {
                    heroChip(profession, icon: professionIcon)
                }

                heroChip("\(profile.height) cm", icon: "ruler.fill")
            }

            HStack(spacing: 8) {
                heroChip(distanceText, icon: "location.fill")

                if let lookingFor = cleanLookingFor {
                    Text(lookingFor)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(accent)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(accent.opacity(0.14))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(accent.opacity(0.42), lineWidth: 1)
                        )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.black.opacity(0.36))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.16), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.38), radius: 20, x: 0, y: 12)
    }

    private func heroChip(_ text: String, icon: String) -> some View {
        Label(text, systemImage: icon)
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundColor(.white.opacity(0.8))
            .lineLimit(1)
            .minimumScaleFactor(0.72)
    }

    // MARK: - Floating Section Nav

    private func floatingSectionNav(proxy: ScrollViewProxy) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(availableSections, id: \.self) { section in
                    Button {
                        activeSection = section
                        withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
                            proxy.scrollTo(section, anchor: .top)
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: section.icon)
                                .font(.system(size: 11, weight: .bold))

                            Text(section.rawValue)
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                        }
                        .foregroundColor(activeSection == section ? .white : AppTheme.textSecondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(
                            activeSection == section
                            ? AnyShapeStyle(AppTheme.primaryGradient)
                            : AnyShapeStyle(AppTheme.surface.opacity(0.72))
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(activeSection == section ? Color.clear : accent.opacity(0.22), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(6)
        }
        .background(AppTheme.cardBackground.opacity(0.88))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(accent.opacity(0.16), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.25), radius: 18, x: 0, y: 10)
    }

    private var availableSections: [ProfileSection] {
        ProfileSection.allCases.filter { section in
            switch section {
            case .details:
                return true
            case .about:
                return !profile.bio.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            case .prompts:
                return !answeredPrompts.isEmpty
            case .photos:
                return !profile.extraPhotos.isEmpty
            case .interests:
                return !profile.interests.isEmpty
            }
        }
    }

    private func sectionContainer<Content: View>(
        _ section: ProfileSection,
        delay: Double = 0,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .id(section)
            .opacity(hasAppeared ? 1 : 0)
            .offset(y: hasAppeared ? 0 : 18)
            .animation(.spring(response: 0.45, dampingFraction: 0.84).delay(delay), value: hasAppeared)
            .onAppear {
                activeSection = section
            }
    }

    // MARK: - Info Panel

    private var infoPanel: some View {
        VStack(alignment: .leading, spacing: 22) {
            sectionContainer(.details) {
                profileSnapshotCard
                    .padding(.horizontal, 20)
            }

            if !profile.bio.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                sectionContainer(.about, delay: 0.04) {
                    aboutSection
                }
            }

            if !answeredPrompts.isEmpty {
                sectionContainer(.prompts, delay: 0.08) {
                    VStack(alignment: .leading, spacing: 12) {
                        sectionTitle("Get to Know Me", icon: "text.bubble.fill")

                        ForEach(answeredPrompts) { prompt in
                            promptCard(prompt)
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }

            let extraPhotos = profile.extraPhotos
            if !extraPhotos.isEmpty {
                sectionContainer(.photos, delay: 0.12) {
                    VStack(alignment: .leading, spacing: 12) {
                        sectionTitle("Moments from life", icon: "photo.stack.fill")
                        photoStoryStack(extraPhotos)
                    }
                    .padding(.horizontal, 20)
                }
            }

            if !profile.interests.isEmpty {
                sectionContainer(.interests, delay: 0.16) {
                    interestsSection
                }
            }
        }
        .padding(.top, 20)
        .padding(.bottom, 28)
    }

    // MARK: - Bento Info Grid

    private var profileSnapshotCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Row 1 — two wide cells
            HStack(spacing: 10) {
                if let profession = cleanProfession {
                    cardBentoCellWide(
                        icon: professionIcon,
                        label: "Job",
                        value: profession,
                        accentColor: accentSecondary,
                        delay: 0
                    )
                }

                cardBentoCellWide(
                    icon: "location.fill",
                    label: "Distance",
                    value: distanceText,
                    accentColor: AppTheme.green,
                    delay: 0.05
                )
            }

            // Row 2 — stat cell + looking for wide
            HStack(spacing: 10) {
                if profile.height > 0 {
                    cardBentoStatCell(
                        icon: "ruler.fill",
                        label: "Height",
                        value: "\(profile.height)",
                        unit: "cm",
                        accentColor: accent,
                        delay: 0.10
                    )
                }

                if let lookingFor = cleanLookingFor {
                    cardBentoCellWide(
                        icon: "heart.fill",
                        label: "Here for",
                        value: lookingFor,
                        accentColor: accent,
                        delay: 0.14
                    )
                } else if let gender = cleanGender {
                    cardBentoCellWide(
                        icon: "person.fill",
                        label: "Gender",
                        value: gender,
                        accentColor: Color(hex: "C44EFF"),
                        delay: 0.14
                    )
                }
            }
        }
    }

    private func cardBentoCellWide(
        icon: String,
        label: String,
        value: String,
        accentColor: Color,
        delay: Double
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .black))
                    .foregroundColor(accentColor)
                Text(label.uppercased())
                    .font(.system(size: 9, weight: .black, design: .rounded))
                    .foregroundColor(AppTheme.textTertiary)
                    .tracking(0.9)
            }

            Text(value)
                .font(.system(size: 15, weight: .black, design: .rounded))
                .foregroundColor(AppTheme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(AppTheme.surface.opacity(0.95))
                RadialGradient(
                    colors: [accentColor.opacity(0.16), .clear],
                    center: .topLeading,
                    startRadius: 6,
                    endRadius: 80
                )
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(accentColor.opacity(0.3), lineWidth: 1)
        )
        .scaleEffect(hasAppeared ? 1 : 0.88)
        .opacity(hasAppeared ? 1 : 0)
        .animation(.spring(response: 0.42, dampingFraction: 0.72).delay(delay), value: hasAppeared)
    }

    private func cardBentoStatCell(
        icon: String,
        label: String,
        value: String,
        unit: String,
        accentColor: Color,
        delay: Double
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .black))
                .foregroundColor(accentColor)

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 20, weight: .black, design: .rounded))
                    .foregroundColor(AppTheme.textPrimary)
                Text(unit)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundColor(AppTheme.textTertiary)
            }

            Text(label.uppercased())
                .font(.system(size: 9, weight: .black, design: .rounded))
                .foregroundColor(AppTheme.textTertiary)
                .tracking(0.9)
        }
        .frame(width: 84, alignment: .leading)
        .padding(12)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(AppTheme.surface.opacity(0.95))
                RadialGradient(
                    colors: [accentColor.opacity(0.18), .clear],
                    center: .topLeading,
                    startRadius: 6,
                    endRadius: 70
                )
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(accentColor.opacity(0.32), lineWidth: 1)
        )
        .scaleEffect(hasAppeared ? 1 : 0.88)
        .opacity(hasAppeared ? 1 : 0)
        .animation(.spring(response: 0.42, dampingFraction: 0.72).delay(delay), value: hasAppeared)
    }

    // MARK: - Cleaned Profile Values

    private var cleanProfession: String? {
        cleanValue(
            profile.profession,
            invalidValues: [
                "other",
                "others",
                "na",
                "n/a",
                "none",
                "null",
                "nil",
                "prefer not to say",
                "not specified",
                "unknown",
                "-"
            ]
        )
    }

    private var cleanLookingFor: String? {
        cleanValue(
            profile.lookingFor,
            invalidValues: [
                "na",
                "n/a",
                "none",
                "null",
                "nil",
                "prefer not to say",
                "not specified",
                "unknown",
                "-"
            ]
        )
    }

    private var cleanGender: String? {
        cleanValue(
            profile.gender,
            invalidValues: [
                "na",
                "n/a",
                "none",
                "null",
                "nil",
                "prefer not to say",
                "not specified",
                "unknown",
                "-"
            ]
        )
    }

    private var answeredPrompts: [UserProfile.Prompt] {
        profile.prompts.filter {
            !$0.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private func cleanValue(_ value: String, invalidValues: Set<String>) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            return nil
        }

        guard !invalidValues.contains(trimmed.lowercased()) else {
            return nil
        }

        return trimmed
    }

    private var distanceText: String {
        if profile.distance <= 0.1 {
            return "Nearby"
        }

        return "\(String(format: "%.1f", profile.distance)) mi away"
    }

    private var professionIcon: String {
        let profession = cleanProfession?.lowercased() ?? ""

        if profession.contains("chef") {
            return "fork.knife"
        }

        if profession.contains("architect") {
            return "building.2.fill"
        }

        if profession.contains("doctor") {
            return "cross.case.fill"
        }

        if profession.contains("engineer") {
            return "hammer.fill"
        }

        if profession.contains("artist") {
            return "paintpalette.fill"
        }

        if profession.contains("designer") {
            return "pencil.and.outline"
        }

        if profession.contains("teacher") {
            return "book.fill"
        }

        if profession.contains("student") {
            return "graduationcap.fill"
        }

        return "briefcase.fill"
    }


    // MARK: - Background

    private var profileBackdrop: some View {
        ZStack {
            cardBase

            LinearGradient(
                colors: [
                    Color(hex: "15151B"),
                    AppTheme.cardBackground,
                    Color(hex: "171124")
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [accent.opacity(0.16), .clear],
                center: .topTrailing,
                startRadius: 40,
                endRadius: 420
            )

            RadialGradient(
                colors: [accentSecondary.opacity(0.13), .clear],
                center: .bottomLeading,
                startRadius: 30,
                endRadius: 380
            )
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("A little about me", icon: "quote.opening")

            Text(profile.bio)
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundColor(AppTheme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(inkPanel)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(accent.opacity(0.18), lineWidth: 1)
        )
        .padding(.horizontal, 20)
    }

    // MARK: - Photos

    private func photoStoryStack(_ photos: [ProfilePhoto]) -> some View {
        VStack(spacing: 14) {
            ForEach(Array(photos.prefix(4).enumerated()), id: \.element.id) { index, photo in
                extraPhotoTile(photo: photo, index: index)
            }
        }
    }

    private func extraPhotoTile(photo: ProfilePhoto, index: Int) -> some View {
        let gradients: [[String]] = [
            ["0F172A", "1E3A5F"],
            ["1A1A2E", "4A1259"],
            ["0D2137", "0E4D3A"],
            ["1C1C1E", "3D2B1F"]
        ]

        let g = gradients[index % gradients.count]
        let photoHeight = index % 2 == 0 ? AppTheme.publicStoryPhotoHeightLeft : AppTheme.publicStoryPhotoHeightRight

        return ZStack(alignment: .bottomLeading) {
            ProfilePhotoView(
                photo: photo,
                symbolName: "photo.fill",
                symbolSize: 72,
                gradientColors: [Color(hex: g[0]), Color(hex: g[1])],
                symbolOpacity: 0.18
            )
            .frame(height: photoHeight)

            LinearGradient(
                colors: [
                    .clear,
                    .black.opacity(0.72)
                ],
                startPoint: .center,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Photo \(index + 2)")
                        .font(.system(size: 11, weight: .black, design: .rounded))
                        .foregroundColor(.white.opacity(0.9))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.black.opacity(0.35))
                        .clipShape(Capsule())

                    Spacer()
                }

                Text(photoConversationHint(index: index))
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
            }
            .padding(16)
        }
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.photoGridCornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.photoGridCornerRadius)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private func photoConversationHint(index: Int) -> String {
        let hints = [
            "Ask about this moment",
            "This looks like a story",
            "A good photo to start with",
            "Ask where this was taken"
        ]

        return hints[index % hints.count]
    }

    // MARK: - Prompts

    private func promptCard(_ prompt: UserProfile.Prompt) -> some View {
        let isExpanded = expandedPromptIDs.contains(prompt.id)

        return VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                    if isExpanded {
                        expandedPromptIDs.remove(prompt.id)
                    } else {
                        expandedPromptIDs.insert(prompt.id)
                    }
                }
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(prompt.question)
                            .font(.system(size: 10, weight: .black, design: .rounded))
                            .foregroundStyle(AppTheme.primaryGradient)
                            .textCase(.uppercase)
                            .tracking(1.0)

                        Text(prompt.answer)
                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                            .foregroundColor(AppTheme.textPrimary)
                            .lineLimit(isExpanded ? nil : 2)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.up.circle.fill" : "chevron.down.circle.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(AppTheme.primaryGradient)
                        .rotationEffect(.degrees(isExpanded ? 0 : 0))
                }
            }
            .buttonStyle(.plain)

            if isExpanded {
                HStack {
                    Text("React to this ✨")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(AppTheme.textTertiary)
                        .transition(.opacity.combined(with: .move(edge: .top)))

                    Spacer()

                    Button(action: {}) {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 14, weight: .black))
                            .foregroundStyle(AppTheme.primaryGradient)
                            .padding(10)
                            .background(
                                Circle()
                                    .fill(AppTheme.pink.opacity(0.14))
                                    .overlay(
                                        Circle()
                                            .stroke(AppTheme.pink.opacity(0.3), lineWidth: 1)
                                    )
                            )
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .padding(18)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(inkPanel)
                if isExpanded {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [accent.opacity(0.08), accentSecondary.opacity(0.05)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .transition(.opacity)
                }
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(
                    isExpanded
                        ? AnyShapeStyle(AppTheme.primaryGradient)
                        : AnyShapeStyle(accent.opacity(0.16)),
                    lineWidth: isExpanded ? 1.2 : 1
                )
        )
        .scaleEffect(isExpanded ? 1.018 : 1)
        .shadow(color: isExpanded ? accent.opacity(0.18) : .clear, radius: 12, x: 0, y: 6)
    }

    // MARK: - Interests

    private var interestsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Things I’m into", icon: "heart.text.square.fill")

            FlowLayout(spacing: 8) {
                ForEach(Array(profile.interests.enumerated()), id: \.element) { index, interest in
                    animatedInterestTag(interest, index: index)
                }
            }
        }
        .padding(.horizontal, 20)
    }

    private func animatedInterestTag(_ interest: String, index: Int) -> some View {
        let tagColors: [Color] = [AppTheme.pink, AppTheme.purple, AppTheme.green, Color(hex: "C44EFF"), Color(hex: "00C8FF")]
        let tagColor = tagColors[abs(interest.hashValue) % tagColors.count]

        return Label(interest, systemImage: interestIcon(interest))
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .foregroundStyle(
                LinearGradient(
                    colors: [tagColor, tagColor.opacity(0.6)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .padding(.horizontal, 13)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(tagColor.opacity(0.1))
                    .overlay(
                        Capsule()
                            .stroke(tagColor.opacity(0.28), lineWidth: 1)
                    )
            )
            .scaleEffect(hasAppeared ? 1 : 0.82)
            .opacity(hasAppeared ? 1 : 0)
            .animation(
                .spring(response: 0.34, dampingFraction: 0.68)
                    .delay(Double(index) * 0.04),
                value: hasAppeared
            )
    }

    // MARK: - Section Title

    private func sectionTitle(_ title: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(AppTheme.primaryGradient)

            Text(title)
                .font(.system(size: 14, weight: .black, design: .rounded))
                .foregroundColor(AppTheme.textPrimary)
                .textCase(.uppercase)
                .tracking(1.3)

            Rectangle()
                .fill(accent.opacity(0.18))
                .frame(height: 1)
        }
    }

    // MARK: - Swipe Badges

    private var swipeBadges: some View {
        ZStack {
            badgeLabel("LIKE", color: AppTheme.green, rotation: -22)
                .opacity(likeOpacity)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.top, 52)
                .padding(.leading, 22)

            badgeLabel("NOPE", color: AppTheme.red, rotation: 22)
                .opacity(nopeOpacity)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(.top, 52)
                .padding(.trailing, 22)

            badgeLabel("SUPER", color: AppTheme.gold, rotation: 0)
                .opacity(superLikeOpacity)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.top, 52)
        }
    }

    private func badgeLabel(_ text: String, color: Color, rotation: Double) -> some View {
        Text(text)
            .font(.system(size: 28, weight: .black, design: .rounded))
            .foregroundColor(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(color.opacity(0.85))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(color, lineWidth: 2.5)
            )
            .shadow(color: color.opacity(0.5), radius: 12, x: 0, y: 0)
            .rotationEffect(.degrees(rotation))
    }

    // MARK: - Helpers

    private var profileGradientColors: [Color] {
        let sets: [[String]] = [
            ["1E1B4B", "7C3AED"],
            ["0F172A", "0E7490"],
            ["1A1A2E", "BE185D"],
            ["0C1445", "1D4ED8"],
            ["14532D", "047857"]
        ]

        let idx = abs(profile.name.hashValue) % sets.count
        let g = sets[idx]

        return [Color(hex: g[0]), Color(hex: g[1])]
    }

    private func interestIcon(_ interest: String) -> String {
        switch interest {
        case "Photography":
            return "camera.fill"
        case "Cooking":
            return "fork.knife"
        case "Karaoke":
            return "music.mic"
        case "Travel":
            return "airplane"
        case "Swimming":
            return "figure.pool.swim"
        case "Running":
            return "figure.run"
        case "Guitar":
            return "guitars.fill"
        case "Writing":
            return "pencil"
        case "Farmers Markets":
            return "leaf.fill"
        case "Wine":
            return "wineglass.fill"
        case "Hiking":
            return "figure.hiking"
        default:
            return "star.fill"
        }
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { onDragChanged?($0) }
            .onEnded { onDragEnded?($0) }
    }
}

// MARK: - Flow Layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        FlowResult(
            in: proposal.replacingUnspecifiedDimensions().width,
            subviews: subviews,
            spacing: spacing
        ).size
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let result = FlowResult(
            in: bounds.width,
            subviews: subviews,
            spacing: spacing
        )

        for (index, frame) in result.frames.enumerated() {
            subviews[index].place(
                at: CGPoint(
                    x: frame.minX + bounds.minX,
                    y: frame.minY + bounds.minY
                ),
                proposal: ProposedViewSize(frame.size)
            )
        }
    }

    struct FlowResult {
        var frames: [CGRect] = []
        var size: CGSize = .zero

        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var x: CGFloat = 0
            var y: CGFloat = 0
            var rowHeight: CGFloat = 0
            var maxX: CGFloat = 0

            for subview in subviews {
                let sz = subview.sizeThatFits(.unspecified)

                if x + sz.width > maxWidth, x > 0 {
                    x = 0
                    y += rowHeight + spacing
                    rowHeight = 0
                }

                frames.append(
                    CGRect(
                        x: x,
                        y: y,
                        width: sz.width,
                        height: sz.height
                    )
                )

                x += sz.width + spacing
                rowHeight = max(rowHeight, sz.height)
                maxX = max(maxX, x - spacing)
            }

            size = CGSize(width: maxX, height: y + rowHeight)
        }
    }
}
