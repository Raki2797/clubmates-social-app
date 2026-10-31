import SwiftUI

struct ProfileFullDetailView: View {
    let profile: UserProfile
    @Binding var photoStoryPage: Int
    @Binding var isPresented: Bool
    var showActions: Bool = true
    @State private var appeared = false
    @State private var scrollOffset: CGFloat = 0
    @Environment(\.tabBarState) private var tabBarState

    var onPass: (() -> Void)? = nil
    var onLike: (() -> Void)? = nil
    var onSuperLike: (() -> Void)? = nil
    var onGift: (() -> Void)? = nil

    var body: some View {
        ZStack {
            AppTheme.background.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    heroCard
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 20)
                        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: appeared)
                        .background(
                            GeometryReader { geo in
                                Color.clear.preference(
                                    key: ScrollOffsetKey.self,
                                    value: geo.frame(in: .named("profileScroll")).minY
                                )
                            }
                        )

                    VStack(alignment: .leading, spacing: 24) {
                        bentoGrid
                            .opacity(appeared ? 1 : 0)
                            .offset(y: appeared ? 0 : 20)
                            .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.06), value: appeared)

                        if !profile.bio.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            bioCard
                                .opacity(appeared ? 1 : 0)
                                .offset(y: appeared ? 0 : 20)
                                .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.11), value: appeared)
                        }

                        if profile.photos.count > 1 {
                            photoGallery
                                .opacity(appeared ? 1 : 0)
                                .offset(y: appeared ? 0 : 20)
                                .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.19), value: appeared)
                        }

                        if !answeredPrompts.isEmpty {
                            getToKnowMe
                                .opacity(appeared ? 1 : 0)
                                .offset(y: appeared ? 0 : 20)
                                .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.15), value: appeared)
                        }

                        if !profile.interests.isEmpty {
                            interestsSection
                                .opacity(appeared ? 1 : 0)
                                .offset(y: appeared ? 0 : 20)
                                .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.23), value: appeared)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 120)
                }
            }
            .coordinateSpace(name: "profileScroll")
            .onPreferenceChange(ScrollOffsetKey.self) { value in
                scrollOffset = value
            }
            .ignoresSafeArea(edges: .top)

            // Close button
            VStack {
                HStack {
                    Spacer()
                    Button(action: { isPresented = false }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 36, height: 36)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(.white.opacity(0.15), lineWidth: 1))
                    }
                    .padding(.top, 56)
                    .padding(.trailing, 20)
                }
                Spacer()
            }

            // Floating action rail
            if showActions {
                VStack {
                    Spacer()
                    SlideActionRail(
                        onPass: {
                            onPass?()
                            isPresented = false
                        },
                        onLike: {
                            onLike?()
                            isPresented = false
                        },
                        onGift: {
                            onGift?()
                            isPresented = false
                        }
                    )
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
                    .background(
                        LinearGradient(
                            colors: [AppTheme.background.opacity(0), AppTheme.background.opacity(0.95), AppTheme.background],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: 120)
                        .allowsHitTesting(false),
                        alignment: .bottom
                    )
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 40)
                    .animation(.spring(response: 0.6, dampingFraction: 0.75).delay(0.3), value: appeared)
                }
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.8).delay(0.05)) {
                appeared = true
            }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                tabBarState?.isHidden = true
            }
        }
        .onDisappear {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                tabBarState?.isHidden = false
            }
        }
    }


    // MARK: - Hero Card

    private var parallaxOffset: CGFloat {
        guard scrollOffset < 0 else { return 0 }
        return scrollOffset * 0.35
    }

    private var heroCard: some View {
        ZStack(alignment: .bottom) {
            ProfilePhotoView(
                photo: profile.mainPhoto,
                symbolName: "person.fill",
                symbolSize: 96,
                gradientColors: [Color(hex: "111827"), Color(hex: "4A1259")],
                symbolOpacity: 0.14,
                contentMode: .fill,
                contentAlignment: .top
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .scaleEffect(1 + max(0, -scrollOffset) / 1200)
            .offset(y: parallaxOffset)

            LinearGradient(
                colors: [.black.opacity(0.45), .clear],
                startPoint: .top,
                endPoint: .init(x: 0.5, y: 0.28)
            )

            VStack(alignment: .leading, spacing: 10) {
                if profile.isVerified {
                    Label("Verified", systemImage: "checkmark.seal.fill")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(AppTheme.green)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(AppTheme.green.opacity(0.18))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(AppTheme.green.opacity(0.45), lineWidth: 1))
                }

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(profile.name)
                        .font(.system(size: 36, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)

                    Text("\(profile.age)")
                        .font(.system(size: 24, weight: .black, design: .rounded))
                        .foregroundColor(.white.opacity(0.72))
                }
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(
                    colors: [.clear, .black.opacity(0.28), .black.opacity(0.82)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
        .frame(maxWidth: .infinity)
        .frame(height: 480)
        .clipped()
        .overlay(
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [.clear, AppTheme.background],
                        startPoint: .init(x: 0.5, y: 0.88),
                        endPoint: .bottom
                    )
                )
        )
    }

    // MARK: - Bento Grid

    private var bentoGrid: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                if let profession = cleanProfession {
                    bentoCellWide(icon: professionIcon, label: "Job", value: profession, accent: AppTheme.purple)
                }
                if profile.height > 0 {
                    bentoCell(icon: "ruler.fill", label: "Height", value: "\(profile.height)", unit: "cm", accent: AppTheme.green)
                }
            }

            HStack(spacing: 10) {
                if let gender = cleanGender {
                    bentoCell(icon: "person.fill", label: "Gender", value: gender, unit: nil, accent: Color(hex: "C44EFF"))
                }
                if let lookingFor = cleanLookingFor {
                    bentoCellWide(icon: "heart.fill", label: "Here for", value: lookingFor, accent: AppTheme.pink)
                }
            }
        }
    }

    private func bentoCellWide(icon: String, label: String, value: String, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .black))
                    .foregroundColor(accent)
                Text(label.uppercased())
                    .font(.system(size: 10, weight: .black, design: .rounded))
                    .foregroundColor(AppTheme.textTertiary)
                    .tracking(1.0)
            }
            Text(value)
                .font(.system(size: 17, weight: .black, design: .rounded))
                .foregroundColor(AppTheme.textPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous).fill(AppTheme.surface)
                RadialGradient(colors: [accent.opacity(0.15), .clear], center: .topLeading, startRadius: 8, endRadius: 100)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        )
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(accent.opacity(0.28), lineWidth: 1))
    }

    private func bentoCell(icon: String, label: String, value: String, unit: String?, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .black))
                .foregroundColor(accent)

            Spacer(minLength: 4)

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(value)
                        .font(.system(size: 22, weight: .black, design: .rounded))
                        .foregroundColor(AppTheme.textPrimary)
                    if let unit {
                        Text(unit)
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundColor(AppTheme.textTertiary)
                    }
                }
                Text(label.uppercased())
                    .font(.system(size: 9, weight: .black, design: .rounded))
                    .foregroundColor(AppTheme.textTertiary)
                    .tracking(1.0)
            }
        }
        .frame(width: 100, alignment: .leading)
        .padding(14)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous).fill(AppTheme.surface)
                RadialGradient(colors: [accent.opacity(0.18), .clear], center: .topLeading, startRadius: 8, endRadius: 90)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        )
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(accent.opacity(0.28), lineWidth: 1))
    }

    // MARK: - Bio

    private var bioCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("About", icon: "quote.opening")
            Text(profile.bio)
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundColor(AppTheme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(5)
        }
        .padding(18)
        .glassCard(accentColor: AppTheme.purple)
    }

    // MARK: - Prompts

    private var getToKnowMe: some View {
        let promptAccents: [Color] = [AppTheme.pink, AppTheme.purple, AppTheme.green]

        return VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Get to Know Me", icon: "text.bubble.fill")

            ForEach(Array(answeredPrompts.enumerated()), id: \.element.id) { i, prompt in
                let accent = promptAccents[i % promptAccents.count]
                HStack(alignment: .top, spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(accent.opacity(0.18))
                            .frame(width: 36, height: 36)
                        Image(systemName: "quote.opening")
                            .font(.system(size: 13, weight: .black))
                            .foregroundColor(accent)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text(prompt.question)
                            .font(.system(size: 11, weight: .black, design: .rounded))
                            .foregroundColor(accent)
                            .textCase(.uppercase)
                            .tracking(0.8)
                        Text(prompt.answer)
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundColor(AppTheme.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .lineSpacing(3)
                    }
                }
                .padding(16)
                .background(
                    ZStack {
                        RoundedRectangle(cornerRadius: 18, style: .continuous).fill(AppTheme.surface)
                        RadialGradient(colors: [accent.opacity(0.1), .clear], center: .topLeading, startRadius: 10, endRadius: 120)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                )
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(accent.opacity(0.22), lineWidth: 1))
            }
        }
    }

    // MARK: - Photo Gallery

    private var photoGallery: some View {
        let extraPhotos = Array(profile.photos.dropFirst())

        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                sectionTitle("More Photos", icon: "photo.stack.fill")
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: "hand.draw.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(AppTheme.textTertiary)
                    Text("Swipe")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundColor(AppTheme.textTertiary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(AppTheme.surface)
                .clipShape(Capsule())
            }

            TabView(selection: $photoStoryPage) {
                ForEach(Array(extraPhotos.enumerated()), id: \.element.id) { index, photo in
                    photoCard(photo: photo, index: index)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: 440)
            .compositingGroup()
            .clipShape(cardShape)
            .background(cardShape.fill(AppTheme.surfaceElevated.opacity(0.92)))
            .overlay(cardShape.stroke(borderGradient, lineWidth: 1.25))
            .shadow(color: .black.opacity(0.26), radius: 18, x: 0, y: 10)

            HStack(spacing: 5) {
                ForEach(0..<extraPhotos.count, id: \.self) { i in
                    if i == photoStoryPage {
                        Capsule()
                            .fill(AppTheme.primaryGradient)
                            .frame(width: 22, height: 6)
                            .shadow(color: AppTheme.pink.opacity(0.55), radius: 4)
                            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: photoStoryPage)
                    } else {
                        Circle()
                            .fill(Color.white.opacity(0.25))
                            .frame(width: 6, height: 6)
                            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: photoStoryPage)
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func photoCard(photo: ProfilePhoto, index: Int) -> some View {
        ZStack(alignment: .bottom) {
            ProfilePhotoView(
                photo: photo,
                symbolName: "photo.fill",
                symbolSize: 64,
                gradientColors: [Color(hex: "121826"), Color(hex: index.isMultiple(of: 2) ? "0E4D3A" : "4A1259")],
                symbolOpacity: 0.16,
                contentMode: .fill,
                contentAlignment: .top
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(cardShape)

            LinearGradient(colors: [.clear, .black.opacity(0.65)], startPoint: .center, endPoint: .bottom)
                .clipShape(cardShape)

            HStack(alignment: .bottom) {
                Spacer(minLength: 10)
                Text("\(index + 1) / \(profile.photos.count - 1)")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.72))
            }
            .padding(16)
        }
        .background(cardShape.fill(AppTheme.surfaceElevated.opacity(0.96)))
        .clipShape(cardShape)
    }

    private func photoBadge(_ title: String, systemImage: String? = nil, tint: Color) -> some View {
        HStack(spacing: 6) {
            if let systemImage {
                Image(systemName: systemImage).font(.system(size: 10, weight: .black))
            }
            Text(title).font(.system(size: 11, weight: .black, design: .rounded)).tracking(0.35)
        }
        .foregroundColor(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(tint)
        .clipShape(Capsule())
    }

    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: AppTheme.photoGridCornerRadius, style: .continuous)
    }

    private var borderGradient: LinearGradient {
        LinearGradient(
            colors: [Color.white.opacity(0.12), AppTheme.pink.opacity(0.22), AppTheme.purple.opacity(0.16), Color.white.opacity(0.08)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    // MARK: - Interests

    private var interestsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("Interests", icon: "sparkles")

            FlowLayout(spacing: 8) {
                ForEach(Array(profile.interests.enumerated()), id: \.element) { idx, interest in
                    interestChip(interest)
                        .opacity(appeared ? 1 : 0)
                        .animation(.easeOut(duration: 0.4).delay(Double(idx) * 0.05), value: appeared)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous).fill(AppTheme.surface)
                RadialGradient(colors: [AppTheme.purple.opacity(0.12), .clear], center: .topTrailing, startRadius: 20, endRadius: 180)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(
                    LinearGradient(colors: [AppTheme.purple.opacity(0.3), AppTheme.pink.opacity(0.15)], startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: 1
                )
        )
    }

    private func interestChip(_ interest: String) -> some View {
        let pairs: [(Color, Color)] = [
            (AppTheme.pink, AppTheme.purple),
            (AppTheme.purple, Color(hex: "C44EFF")),
            (AppTheme.green, Color(hex: "00C8FF")),
            (Color(hex: "C44EFF"), AppTheme.pink),
        ]
        let pair = pairs[abs(interest.hashValue) % pairs.count]

        return Label(interest, systemImage: interestIcon(interest))
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .foregroundStyle(LinearGradient(colors: [pair.0, pair.1], startPoint: .topLeading, endPoint: .bottomTrailing))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Capsule().fill(pair.0.opacity(0.1)).overlay(Capsule().stroke(pair.0.opacity(0.3), lineWidth: 1)))
    }

    // MARK: - Helpers

    private func sectionTitle(_ title: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(AppTheme.primaryGradient)
            Text(title)
                .font(.system(size: 18, weight: .black, design: .rounded))
                .foregroundColor(AppTheme.textPrimary)
        }
    }

    private var answeredPrompts: [UserProfile.Prompt] {
        profile.prompts.filter { !$0.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private var cleanProfession: String? {
        cleanValue(profile.profession, invalid: ["other","others","na","n/a","none","null","nil","prefer not to say","not specified","unknown","-"])
    }

    private var cleanLookingFor: String? {
        cleanValue(profile.lookingFor, invalid: ["na","n/a","none","null","nil","prefer not to say","not specified","unknown","-"])
    }

    private var cleanGender: String? {
        cleanValue(profile.gender, invalid: ["na","n/a","none","null","nil","prefer not to say","not specified","unknown","-"])
    }

    private func cleanValue(_ value: String, invalid: Set<String>) -> String? {
        let t = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, !invalid.contains(t.lowercased()) else { return nil }
        return t
    }

    private var professionIcon: String {
        let p = cleanProfession?.lowercased() ?? ""
        if p.contains("chef") { return "fork.knife" }
        if p.contains("architect") { return "building.2.fill" }
        if p.contains("doctor") { return "cross.case.fill" }
        if p.contains("engineer") { return "hammer.fill" }
        if p.contains("artist") { return "paintpalette.fill" }
        if p.contains("designer") { return "pencil.and.outline" }
        if p.contains("teacher") { return "book.fill" }
        if p.contains("student") { return "graduationcap.fill" }
        return "briefcase.fill"
    }

    private func interestIcon(_ interest: String) -> String {
        switch interest {
        case "Baking": return "birthday.cake"
        case "Code": return "laptopcomputer"
        case "Hiking": return "figure.hiking"
        case "Concerts": return "music.note"
        case "Coffee": return "cup.and.saucer.fill"
        case "Vinyl": return "opticaldisc"
        case "Travel": return "airplane"
        case "Cooking": return "fork.knife"
        case "Yoga": return "figure.yoga"
        case "Books": return "books.vertical.fill"
        case "Surfing": return "figure.surfing"
        case "Dogs": return "pawprint.fill"
        case "Photography": return "camera.fill"
        case "Guitar": return "guitars.fill"
        case "Writing": return "pencil"
        case "Farmers Markets": return "leaf.fill"
        case "Wine": return "wineglass.fill"
        default: return "star.fill"
        }
    }
}


