import SwiftUI
import UniformTypeIdentifiers

struct OnboardingBasicsView: View {
    @Binding var draft: UserProfile
    let onNext: () -> Void

    private let maxPhotos = 6
    private let photoGridSpacing: CGFloat = AppTheme.photoGridSpacing
    private let photoTileCornerRadius: CGFloat = AppTheme.photoTileCornerRadius

    @State private var draggedPhotoID: UUID? = nil

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
                        photoSection
                        basicInfoSection
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
            // Back placeholder (step 1 has no back)
            Color.clear
                .frame(width: 42, height: 42)

            Spacer()

            VStack(spacing: 4) {
                Text("ClubMates")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundColor(AppTheme.textPrimary)
                Text("Step 1 of 3")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(AppTheme.textSecondary)
            }

            Spacer()

            HStack(spacing: 4) {
                ForEach(0..<3) { i in
                    Capsule()
                        .fill(i == 0 ? AnyShapeStyle(AppTheme.primaryGradient) : AnyShapeStyle(AppTheme.textTertiary.opacity(0.45)))
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
                Image(systemName: "camera.fill")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundColor(.white)
            }

            Text("Your Photos & Basics")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(AppTheme.textPrimary)

            Text("Add at least one photo and fill in your details. This is what others will see first.")
                .font(.system(size: 14, design: .rounded))
                .foregroundColor(AppTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(AppTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous))
    }

    // MARK: - Photos

    private var photoSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Photos")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundColor(AppTheme.textPrimary)
                Spacer()
                Text("\(draft.photos.count)/\(maxPhotos)")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(AppTheme.textSecondary)
            }

            // Bento grid:
            //  ┌──────────────────┬──────┐
            //  │      [0]         │ [1]  │
            //  │   (hero 2/3 W)   ├──────┤
            //  │                  │ [2]  │
            //  ├──────────┬───────┴──────┤
            //  │   [3]    │  [4]  │ [5]  │  ← diagonal step
            //  └──────────┴───────┴──────┘
            GeometryReader { geo in
                let gap   = photoGridSpacing
                let totalW = geo.size.width
                let rightW = (totalW - gap) / 3           // right column = 1/3
                let heroW  = totalW - rightW - gap         // hero = 2/3
                let rightH = rightW                        // right tiles are square
                let heroH  = rightH * 2 + gap              // hero spans both right tiles
                let bottomH = rightW                       // bottom row same height as right tiles
                let halfW  = (heroW - gap) / 2            // each of the 2 bottom-left tiles

                VStack(spacing: gap) {
                    // Top row: hero + 2 stacked right tiles
                    HStack(alignment: .top, spacing: gap) {
                        photoSlot(at: 0).frame(width: heroW, height: heroH)
                        VStack(spacing: gap) {
                            photoSlot(at: 1).frame(width: rightW, height: rightH)
                            photoSlot(at: 2).frame(width: rightW, height: rightH)
                        }
                    }

                    // Bottom row: 2 tiles under hero + 1 "diagonal" tile continuing right column
                    HStack(spacing: gap) {
                        photoSlot(at: 3).frame(width: halfW,  height: bottomH)
                        photoSlot(at: 4).frame(width: halfW,  height: bottomH)
                        photoSlot(at: 5).frame(width: rightW, height: bottomH)
                    }
                }
            }
            .frame(height: {
                let w     = UIScreen.main.bounds.width - 40
                let gap   = photoGridSpacing
                let rightW = (w - gap) / 3
                let rightH = rightW
                let heroH  = rightH * 2 + gap
                let bottomH = rightW
                return heroH + gap + bottomH
            }())

            Text("Your first photo is the main one. Tap to replace, + to add, × to remove.")
                .font(.system(size: 12, design: .rounded))
                .foregroundColor(AppTheme.textTertiary)
        }
    }

    @ViewBuilder
    private func photoSlot(at index: Int) -> some View {

        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if index < draft.photos.count {
                    filledPhotoSlot(photo: draft.photos[index], index: index)
                } else if index == draft.photos.count {
                    addPhotoSlot
                } else {
                    emptyPhotoSlot(index: index)
                }
            }
    }

    private func filledPhotoSlot(photo: ProfilePhoto, index: Int) -> some View {
        ZStack(alignment: .topTrailing) {
            PhotoLibraryPickerButton(onPhotoPicked: { replacePhoto(at: index, with: $0) }) {
                ZStack {
                    ProfilePhotoView(
                        photo: photo,
                        symbolName: "photo.fill",
                        symbolSize: 30
                    )

                    LinearGradient(
                        colors: [.clear, .black.opacity(0.42)],
                        startPoint: .center,
                        endPoint: .bottom
                    )

                    VStack(alignment: .leading, spacing: 0) {
                        Spacer()

                        VStack(alignment: .leading, spacing: 6) {
                            if index == 0 {
                                Text("Main")
                                    .font(.system(size: 10, weight: .bold, design: .rounded))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(AppTheme.primaryGradient)
                                    .clipShape(Capsule())
                            }

                            if index != 0 {
                                Text("Photo \(index + 1)")
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                                    .foregroundColor(.white)
                            }
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if canDragPhoto(at: index) {
                        Image(systemName: "line.3.horizontal")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white.opacity(0.9))
                            .frame(width: 28, height: 28)
                            .background(Color.black.opacity(0.48))
                            .clipShape(Circle())
                            .padding(8)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(AppTheme.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: photoTileCornerRadius, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: photoTileCornerRadius, style: .continuous))
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Button(action: { removePhoto(at: index) }) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 28, height: 28)
                    .background(Color.black.opacity(0.68))
                    .clipShape(Circle())
            }
            .padding(8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .opacity(draggedPhotoID == photo.id ? 0.58 : 1)
        .photoDrag(
            enabled: canDragPhoto(at: index),
            photoID: photo.id,
            draggedPhotoID: $draggedPhotoID
        )
        .onDrop(
            of: [UTType.text],
            delegate: OnboardingPhotoReorderDropDelegate(
                destinationID: photo.id,
                photos: $draft.photos,
                draggedPhotoID: $draggedPhotoID
            )
        )
    }

    private var addPhotoSlot: some View {
        PhotoLibraryPickerButton(
            maxSelectionCount: maxPhotos - draft.photos.count,
            onPhotosPicked: appendPhotos
        ) {
            RoundedRectangle(cornerRadius: photoTileCornerRadius, style: .continuous)
                .fill(AppTheme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: photoTileCornerRadius, style: .continuous)
                        .stroke(style: StrokeStyle(lineWidth: 1.5, dash: [5]))
                        .foregroundColor(AppTheme.textTertiary.opacity(0.9))
                )
                .overlay {
                    VStack(spacing: 8) {
                        Image(systemName: "plus")
                            .font(.system(size: 24, weight: .medium))
                            .foregroundStyle(AppTheme.primaryGradient)
                        Text("Add Photo")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundColor(AppTheme.textSecondary)
                    }
                }
                .contentShape(RoundedRectangle(cornerRadius: photoTileCornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func emptyPhotoSlot(index: Int) -> some View {
        RoundedRectangle(cornerRadius: photoTileCornerRadius, style: .continuous)
            .fill(AppTheme.surface.opacity(0.55))
            .overlay(
                RoundedRectangle(cornerRadius: photoTileCornerRadius, style: .continuous)
                    .stroke(AppTheme.textTertiary.opacity(0.18), lineWidth: 1)
            )
            .overlay {
                VStack(spacing: 6) {
                    Image(systemName: "photo")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(AppTheme.textTertiary.opacity(0.75))
                    Text("Photo \(index + 1)")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(AppTheme.textTertiary)
                }
            }
    }

    // MARK: - Basic Info

    private var basicInfoSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionLabel("About")

            VStack(spacing: 10) {
                // Name
                HStack {
                    Text("Name")
                        .font(.system(size: 15, design: .rounded))
                        .foregroundColor(AppTheme.textSecondary)
                        .frame(width: 80, alignment: .leading)
                    TextField("Your name", text: $draft.name)
                        .font(.system(size: 15, design: .rounded))
                        .foregroundColor(AppTheme.textPrimary)
                        .multilineTextAlignment(.trailing)
                        .tint(AppTheme.pink)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(AppTheme.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppTheme.pink.opacity(0.12), lineWidth: 1))

                // Age slider
                OnboardingSliderField(
                    icon: "birthday.cake.fill",
                    label: "Age",
                    valueLabel: "\(draft.age)",
                    subLabel: nil,
                    minLabel: "18",
                    maxLabel: "60",
                    value: Binding(get: { Double(draft.age) }, set: { draft.age = Int($0) }),
                    range: 18...60,
                    step: 1
                )

                // Profession picker
                HStack {
                    Text("Profession")
                        .font(.system(size: 15, design: .rounded))
                        .foregroundColor(AppTheme.textSecondary)
                        .frame(width: 80, alignment: .leading)
                    Spacer()
                    Picker("Profession", selection: $draft.profession) {
                        ForEach(EditProfileView.professionOptions, id: \.self) { option in
                            Text(option).tag(option)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(AppTheme.pink)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(AppTheme.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppTheme.pink.opacity(0.12), lineWidth: 1))

                // Gender picker
                HStack {
                    Text("Gender")
                        .font(.system(size: 15, design: .rounded))
                        .foregroundColor(AppTheme.textSecondary)
                        .frame(width: 80, alignment: .leading)
                    Spacer()
                    Picker("Gender", selection: $draft.gender) {
                        ForEach(["Male", "Female", "Non-binary"], id: \.self) { option in
                            Text(option).tag(option)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(AppTheme.pink)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(AppTheme.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppTheme.pink.opacity(0.12), lineWidth: 1))

                // Height slider
                OnboardingSliderField(
                    icon: "ruler.fill",
                    label: "Height",
                    valueLabel: "\(draft.height) cm",
                    subLabel: cmToFeet(draft.height),
                    minLabel: "140",
                    maxLabel: "220",
                    value: Binding(get: { Double(draft.height) }, set: { draft.height = Int($0) }),
                    range: 140...220,
                    step: 1
                )

                // Bio
                VStack(alignment: .leading, spacing: 6) {
                    ZStack(alignment: .topLeading) {
                        if draft.bio.isEmpty {
                            Text("Write something about yourself...")
                                .font(.system(size: 15, design: .rounded))
                                .foregroundColor(AppTheme.textTertiary)
                                .padding(.horizontal, 16)
                                .padding(.top, 44)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Bio")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundColor(AppTheme.pink)
                                .padding(.horizontal, 16)
                                .padding(.top, 12)
                            TextEditor(text: $draft.bio)
                                .font(.system(size: 15, design: .rounded))
                                .foregroundColor(AppTheme.textPrimary)
                                .scrollContentBackground(.hidden)
                                .padding(.horizontal, 12)
                                .frame(minHeight: 120, maxHeight: 160)
                        }
                    }
                    .background(AppTheme.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppTheme.pink.opacity(0.12), lineWidth: 1))

                    HStack {
                        Spacer()
                        Text("\(draft.bio.count)/150")
                            .font(.system(size: 11, design: .rounded))
                            .foregroundColor(draft.bio.count > 150 ? AppTheme.red : AppTheme.textTertiary)
                    }
                }
            }
        }
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        VStack(spacing: 0) {
            Divider()
                .background(AppTheme.surface)
            Button(action: {
                if canContinue {
                    onNext()
                }
            }) {
                Text("Continue")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(
                        canContinue
                            ? AnyShapeStyle(AppTheme.primaryGradient)
                            : AnyShapeStyle(AppTheme.surface)
                    )
                    .clipShape(Capsule())
            }
            .disabled(!canContinue)
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 16)
        }
        .background(AppTheme.background)
    }

    // MARK: - Helpers

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 18, weight: .semibold, design: .rounded))
            .foregroundColor(AppTheme.textPrimary)
    }

    private func cmToFeet(_ cm: Int) -> String {
        let totalInches = Double(cm) / 2.54
        let feet = Int(totalInches) / 12
        let inches = Int(totalInches) % 12
        return "\(feet)'\(inches)\""
    }

    private var canContinue: Bool {
        draft.photos.count >= 1
            && !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (18...99).contains(draft.age)
            && !draft.bio.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Photo mutations

    private func replacePhoto(at index: Int, with newPhoto: ProfilePhoto) {
        guard draft.photos.indices.contains(index) else { return }
        draft.photos[index].source = newPhoto.source
    }

    private func appendPhoto(_ newPhoto: ProfilePhoto) {
        guard draft.photos.count < maxPhotos else { return }
        draft.photos.append(newPhoto)
    }

    private func appendPhotos(_ newPhotos: [ProfilePhoto]) {
        for photo in newPhotos {
            guard draft.photos.count < maxPhotos else { break }
            draft.photos.append(photo)
        }
    }

    private func removePhoto(at index: Int) {
        guard draft.photos.indices.contains(index) else { return }
        draft.photos.remove(at: index)
    }

    private func canDragPhoto(at index: Int) -> Bool {
        EditProfileView.canDragPhoto(at: index, photoCount: draft.photos.count)
    }
}

// MARK: - photoDrag modifier (file-local)

private extension View {
    @ViewBuilder
    func photoDrag(
        enabled: Bool,
        photoID: UUID,
        draggedPhotoID: Binding<UUID?>
    ) -> some View {
        if enabled {
            self.onDrag {
                draggedPhotoID.wrappedValue = photoID
                return NSItemProvider(object: photoID.uuidString as NSString)
            }
        } else {
            self
        }
    }
}

// MARK: - Drop delegate (file-local)

private struct OnboardingPhotoReorderDropDelegate: DropDelegate {
    let destinationID: UUID
    @Binding var photos: [ProfilePhoto]
    @Binding var draggedPhotoID: UUID?

    func dropEntered(info: DropInfo) {
        guard
            let draggedPhotoID,
            draggedPhotoID != destinationID
        else { return }

        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
            EditProfileView.movePhoto(
                in: &photos,
                draggedPhotoID: draggedPhotoID,
                destinationID: destinationID
            )
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedPhotoID = nil
        return true
    }
}

// MARK: - SliderField (file-local)

private struct OnboardingSliderField: View {
    let icon: String
    let label: String
    let valueLabel: String
    let subLabel: String?
    let minLabel: String
    let maxLabel: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppTheme.primaryGradient)
                    .frame(width: 30, height: 30)
                    .background(AppTheme.pink.opacity(0.12))
                    .clipShape(Circle())

                Text(label)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(AppTheme.textPrimary)

                Spacer()

                HStack(spacing: 4) {
                    Text(valueLabel)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.primaryGradient)
                    if let sub = subLabel {
                        Text("· \(sub)")
                            .font(.system(size: 13, design: .rounded))
                            .foregroundColor(AppTheme.textSecondary)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(AppTheme.pink.opacity(0.1))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(AppTheme.pink.opacity(0.25), lineWidth: 1))
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 8)

            Slider(value: $value, in: range, step: step)
                .tint(AppTheme.pink)
                .padding(.horizontal, 16)

            HStack {
                Text(minLabel)
                Spacer()
                Text(maxLabel)
            }
            .font(.system(size: 11, design: .rounded))
            .foregroundColor(AppTheme.textTertiary)
            .padding(.horizontal, 20)
            .padding(.top, 2)
            .padding(.bottom, 12)
        }
        .background(AppTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppTheme.pink.opacity(0.12), lineWidth: 1))
    }
}
