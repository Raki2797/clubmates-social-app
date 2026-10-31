import SwiftUI
import UniformTypeIdentifiers

struct EditProfileView: View {
    enum Mode {
        case editing
        case creating
    }

    @Binding var profile: UserProfile
    @Environment(\.dismiss) private var dismiss

    private let mode: Mode
    private let onSave: ((UserProfile) -> Void)?
    private let onCancel: (() -> Void)?
    private let maxPhotos = 6
    private let photoGridSpacing: CGFloat = AppTheme.photoGridSpacing
    private let photoTileCornerRadius: CGFloat = AppTheme.photoTileCornerRadius

    @State private var draft: UserProfile
    @State private var editingPromptIndex: Int? = nil
    @State private var showPromptPicker = false
    @State private var showInterestPicker = false
    @State private var showPreferences = false
    @State private var draggedPhotoID: UUID? = nil

    init(
        profile: Binding<UserProfile>,
        mode: Mode = .editing,
        onSave: ((UserProfile) -> Void)? = nil,
        onCancel: (() -> Void)? = nil
    ) {
        self._profile = profile
        self.mode = mode
        self.onSave = onSave
        self.onCancel = onCancel
        self._draft = State(initialValue: profile.wrappedValue)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.background.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 28) {
                        if isCreatingProfile {
                            onboardingIntro
                        }
                        photoSection
                        basicInfoSection
                        promptsSection
                        interestsSection
                        if isCreatingProfile {
                            inlinePreferencesSection
                        } else {
                            preferencesLinkSection
                        }
                    }
                    .padding(.top, 20)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle(navigationTitleText)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(AppTheme.cardBackground, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if isCreatingProfile {
                        if let onCancel {
                            Button("Start Over") { onCancel() }
                                .foregroundColor(AppTheme.textSecondary)
                                .font(.system(size: 16, design: .rounded))
                        }
                    } else {
                        Button("Cancel") { dismiss() }
                            .foregroundColor(AppTheme.textSecondary)
                            .font(.system(size: 16, design: .rounded))
                    }
                }
                if isCreatingProfile {
                    ToolbarItem(placement: .principal) {
                        HStack(spacing: 4) {
                            ForEach(0..<4) { i in
                                Capsule()
                                    .fill(AppTheme.pink)
                                    .frame(width: 16, height: 6)
                            }
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(submitButtonTitle, action: submitDraft)
                    .foregroundStyle(canSubmit ? AnyShapeStyle(AppTheme.primaryGradient) : AnyShapeStyle(Color(AppTheme.textTertiary)))
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .disabled(!canSubmit)
                }
            }
            .sheet(isPresented: $showPromptPicker) {
                if let idx = editingPromptIndex {
                    PromptEditorView(prompt: $draft.prompts[idx])
                }
            }
            .sheet(isPresented: $showInterestPicker) {
                InterestPickerView(selected: $draft.interests)
            }
            .sheet(isPresented: $showPreferences) {
                PreferencesView(preferences: $draft.preferences, lookingFor: $draft.lookingFor, isGhostMode: $draft.isGhostMode)
            }
        }
    }

    private var onboardingIntro: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Create Your Profile")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundColor(AppTheme.textPrimary)

            Text("Finish the basics to unlock the app. Name, age, and bio are required. Everything else can be refined later.")
                .font(.system(size: 14, design: .rounded))
                .foregroundColor(AppTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(AppTheme.primaryGradient)
                Text("Profile creation is required before entering the app.")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(AppTheme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
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
            .padding(.horizontal, 20)

            if !draft.verificationMismatchedPhotoIds.isEmpty {
                mismatchedPhotosBanner
            }

            VStack(spacing: photoGridSpacing) {
                ForEach(photoRowIndices, id: \.self) { row in
                    HStack(spacing: photoGridSpacing) {
                        ForEach(row, id: \.self) { index in
                            photoSlot(at: index)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)

            Text("Your first photo is the main one. Tap a filled slot to replace it, tap + to add a new photo, or use x to remove one.")
                .font(.system(size: 12, design: .rounded))
                .foregroundColor(AppTheme.textTertiary)
                .padding(.horizontal, 20)
        }
    }

    private var mismatchedPhotosBanner: some View {
        let count = draft.verificationMismatchedPhotoIds.count
        return HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(AppTheme.gold)
            Text("\(count) photo\(count == 1 ? "" : "s") didn't match your selfie — replace \(count == 1 ? "it" : "them") to re-verify.")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundColor(AppTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.gold.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(AppTheme.gold.opacity(0.3), lineWidth: 1)
        )
        .padding(.horizontal, 20)
    }

    private var photoRowIndices: [[Int]] {
        stride(from: 0, to: maxPhotos, by: 3).map { start in
            Array(start ..< min(start + 3, maxPhotos))
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

            if draft.verificationMismatchedPhotoIds.map { $0.lowercased() }.contains(photo.id.uuidString.lowercased()) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(AppTheme.gold)
                    .frame(width: 26, height: 26)
                    .background(Color.black.opacity(0.6))
                    .clipShape(Circle())
                    .padding(8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(
            RoundedRectangle(cornerRadius: photoTileCornerRadius, style: .continuous)
                .stroke(Color.red.opacity(draft.verificationMismatchedPhotoIds.map { $0.lowercased() }.contains(photo.id.uuidString.lowercased()) ? 0.85 : 0), lineWidth: 2.5)
        )
        .opacity(draggedPhotoID == photo.id ? 0.58 : 1)
        .photoDrag(
            enabled: canDragPhoto(at: index),
            photoID: photo.id,
            draggedPhotoID: $draggedPhotoID
        )
        .onDrop(
            of: [UTType.text],
            delegate: PhotoReorderDropDelegate(
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
                        .editFieldStyle()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(AppTheme.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppTheme.pink.opacity(0.12), lineWidth: 1))
                .padding(.horizontal, 20)

                // Age slider
                SliderField(
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
                .padding(.horizontal, 20)

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
                .padding(.horizontal, 20)

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
                .padding(.horizontal, 20)

                // Height slider
                SliderField(
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
                .padding(.horizontal, 20)

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
                .padding(.horizontal, 20)
            }
        }
    }

    // MARK: - Prompts
    private var promptsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                sectionLabel("Get to Know Me")
                Spacer()
                if draft.prompts.count < 3 {
                    Button(action: {
                        draft.prompts.append(.init(question: PromptEditorView.questions[0], answer: ""))
                        editingPromptIndex = draft.prompts.count - 1
                        showPromptPicker = true
                    }) {
                        Label("Add", systemImage: "plus")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(AppTheme.primaryGradient)
                    }
                    .padding(.trailing, 20)
                }
            }

            ForEach(Array(draft.prompts.enumerated()), id: \.element.id) { index, prompt in
                promptRow(prompt: prompt, index: index)
            }
        }
    }

    private func promptRow(prompt: UserProfile.Prompt, index: Int) -> some View {
        Button(action: {
            editingPromptIndex = index
            showPromptPicker = true
        }) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(prompt.question)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundColor(AppTheme.pink)
                        .textCase(.uppercase)
                        .tracking(0.6)
                    Text(prompt.answer.isEmpty ? "Tap to answer..." : prompt.answer)
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundColor(prompt.answer.isEmpty ? AppTheme.textTertiary : AppTheme.textPrimary)
                        .lineLimit(2)
                }
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "pencil")
                        .font(.system(size: 14))
                        .foregroundColor(AppTheme.textSecondary)
                    Button(action: { draft.prompts.remove(at: index) }) {
                        Image(systemName: "trash")
                            .font(.system(size: 13))
                            .foregroundColor(AppTheme.red.opacity(0.7))
                    }
                }
            }
            .padding(16)
            .background(AppTheme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(AppTheme.pink.opacity(0.12), lineWidth: 1)
            )
            .padding(.horizontal, 20)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Interests
    private var interestsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                sectionLabel("Interests")
                Spacer()
                Button(action: { showInterestPicker = true }) {
                    Label("Edit", systemImage: "pencil")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.primaryGradient)
                }
                .padding(.trailing, 20)
            }

            FlowLayout(spacing: 8) {
                ForEach(draft.interests, id: \.self) { interest in
                    HStack(spacing: 4) {
                        Text(interest)
                        Button(action: {
                            draft.interests.removeAll { $0 == interest }
                        }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 9, weight: .bold))
                        }
                    }
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(AppTheme.textPrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(AppTheme.surface)
                    .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 20)
        }
    }

    // MARK: - Helpers
    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 18, weight: .semibold, design: .rounded))
            .foregroundColor(AppTheme.textPrimary)
            .padding(.horizontal, 20)
    }

    private func editRow<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 15, design: .rounded))
                .foregroundColor(AppTheme.textSecondary)
                .frame(width: 80, alignment: .leading)
            content()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(AppTheme.cardBackground)
    }

    private func replacePhoto(at index: Int, with newPhoto: ProfilePhoto) {
        guard draft.photos.indices.contains(index) else { return }
        let oldId = draft.photos[index].id.uuidString.lowercased()
        draft.verificationMismatchedPhotoIds.removeAll { $0.lowercased() == oldId }
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
        Self.canDragPhoto(at: index, photoCount: draft.photos.count)
    }

    static func canDragPhoto(at index: Int, photoCount: Int) -> Bool {
        guard index >= 0, index < photoCount else { return false }
        return index != 0 || photoCount > 1
    }

    @discardableResult
    static func movePhoto(
        in photos: inout [ProfilePhoto],
        draggedPhotoID: UUID,
        destinationID: UUID
    ) -> Bool {
        guard
            draggedPhotoID != destinationID,
            let sourceIndex = photos.firstIndex(where: { $0.id == draggedPhotoID }),
            let destinationIndex = photos.firstIndex(where: { $0.id == destinationID }),
            canMovePhoto(from: sourceIndex, to: destinationIndex, photoCount: photos.count)
        else { return false }

        let movedPhoto = photos.remove(at: sourceIndex)
        photos.insert(movedPhoto, at: destinationIndex)
        return true
    }

    static func canMovePhoto(from sourceIndex: Int, to destinationIndex: Int, photoCount: Int) -> Bool {
        guard sourceIndex >= 0,
              sourceIndex < photoCount,
              destinationIndex >= 0,
              destinationIndex < photoCount
        else { return false }

        if photoCount < 2 && (sourceIndex == 0 || destinationIndex == 0) {
            return false
        }

        return true
    }

    static let professionOptions: [String] = [
        "Student", "Engineer", "Doctor", "Designer", "Artist",
        "Chef", "Teacher", "Lawyer", "Entrepreneur", "Nurse",
        "Architect", "Photographer", "Writer", "Musician", "Athlete",
        "Marketing", "Finance", "Scientist", "Developer", "Other"
    ]

    static let lookingForOptions: [String] = [
        "Dating", "Something Casual", "Friendship", "Open to Anything"
    ]

    private var inlinePreferencesSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionLabel("Who Are You Looking For?")

            Text("These can be changed anytime from your profile settings.")
                .font(.system(size: 13, design: .rounded))
                .foregroundColor(AppTheme.textSecondary)
                .padding(.horizontal, 20)

            // Looking For
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppTheme.primaryGradient)
                        .frame(width: 30, height: 30)
                        .background(AppTheme.pink.opacity(0.12))
                        .clipShape(Circle())
                    Text("Looking For")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundColor(AppTheme.textPrimary)
                }
                FlowLayout(spacing: 10) {
                    ForEach(EditProfileView.lookingForOptions, id: \.self) { option in
                        let isSelected = draft.lookingFor == option
                        Button(action: { draft.lookingFor = isSelected ? "" : option }) {
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
            .padding(16)
            .background(AppTheme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppTheme.pink.opacity(0.12), lineWidth: 1))
            .padding(.horizontal, 20)

            // Age range
            VStack(spacing: 10) {
                HStack {
                    Image(systemName: "birthday.cake.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppTheme.primaryGradient)
                        .frame(width: 30, height: 30)
                        .background(AppTheme.pink.opacity(0.12))
                        .clipShape(Circle())
                    Text("Age Range")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundColor(AppTheme.textPrimary)
                    Spacer()
                    Text("\(draft.preferences.ageMin) – \(draft.preferences.ageMax)")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.primaryGradient)
                        .padding(.horizontal, 12).padding(.vertical, 5)
                        .background(AppTheme.pink.opacity(0.1))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(AppTheme.pink.opacity(0.25), lineWidth: 1))
                }
                HStack(spacing: 0) {
                    Text("Min  ")
                        .font(.system(size: 13, design: .rounded))
                        .foregroundColor(AppTheme.textSecondary)
                    Slider(
                        value: Binding(get: { Double(draft.preferences.ageMin) }, set: {
                            draft.preferences.ageMin = min(Int($0), draft.preferences.ageMax - 1)
                        }),
                        in: 18...60, step: 1
                    ).tint(AppTheme.pink)
                }
                HStack(spacing: 0) {
                    Text("Max  ")
                        .font(.system(size: 13, design: .rounded))
                        .foregroundColor(AppTheme.textSecondary)
                    Slider(
                        value: Binding(get: { Double(draft.preferences.ageMax) }, set: {
                            draft.preferences.ageMax = max(Int($0), draft.preferences.ageMin + 1)
                        }),
                        in: 18...60, step: 1
                    ).tint(AppTheme.pink)
                }
            }
            .padding(16)
            .background(AppTheme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppTheme.pink.opacity(0.12), lineWidth: 1))
            .padding(.horizontal, 20)

            // Gender preference
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppTheme.primaryGradient)
                        .frame(width: 30, height: 30)
                        .background(AppTheme.pink.opacity(0.12))
                        .clipShape(Circle())
                    Text("Show Me")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundColor(AppTheme.textPrimary)
                    Spacer()
                }
                FlowLayout(spacing: 10) {
                    ForEach(["Men", "Women", "Non-binary", "Everyone"], id: \.self) { option in

                        let isEveryone = option == "Everyone"
                        let isSelected = isEveryone
                            ? draft.preferences.genders.isEmpty
                            : draft.preferences.genders.contains(option)
                        Button(action: {
                            if isEveryone {
                                draft.preferences.genders = []
                            } else if draft.preferences.genders.contains(option) {
                                draft.preferences.genders.removeAll { $0 == option }
                            } else {
                                draft.preferences.genders.append(option)
                            }
                        }) {
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
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(AppTheme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppTheme.pink.opacity(0.12), lineWidth: 1))
            .padding(.horizontal, 20)

            // Height range
            VStack(spacing: 10) {
                HStack {
                    Image(systemName: "ruler.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppTheme.primaryGradient)
                        .frame(width: 30, height: 30)
                        .background(AppTheme.pink.opacity(0.12))
                        .clipShape(Circle())
                    Text("Height Range")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundColor(AppTheme.textPrimary)
                    Spacer()
                    Text("\(draft.preferences.heightMin) – \(draft.preferences.heightMax) cm")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.primaryGradient)
                        .padding(.horizontal, 12).padding(.vertical, 5)
                        .background(AppTheme.pink.opacity(0.1))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(AppTheme.pink.opacity(0.25), lineWidth: 1))
                }
                HStack(spacing: 0) {
                    Text("Min  ")
                        .font(.system(size: 13, design: .rounded))
                        .foregroundColor(AppTheme.textSecondary)
                    Slider(
                        value: Binding(get: { Double(draft.preferences.heightMin) }, set: {
                            draft.preferences.heightMin = min(Int($0), draft.preferences.heightMax - 1)
                        }),
                        in: 140...220, step: 1
                    ).tint(AppTheme.pink)
                }
                HStack(spacing: 0) {
                    Text("Max  ")
                        .font(.system(size: 13, design: .rounded))
                        .foregroundColor(AppTheme.textSecondary)
                    Slider(
                        value: Binding(get: { Double(draft.preferences.heightMax) }, set: {
                            draft.preferences.heightMax = max(Int($0), draft.preferences.heightMin + 1)
                        }),
                        in: 140...220, step: 1
                    ).tint(AppTheme.pink)
                }
                HStack {
                    Text("140 cm")
                    Spacer()
                    Text("220 cm")
                }
                .font(.system(size: 11, design: .rounded))
                .foregroundColor(AppTheme.textTertiary)
            }
            .padding(16)
            .background(AppTheme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppTheme.pink.opacity(0.12), lineWidth: 1))
            .padding(.horizontal, 20)

            // Verified only toggle
            HStack(spacing: 12) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppTheme.primaryGradient)
                    .frame(width: 30, height: 30)
                    .background(AppTheme.pink.opacity(0.12))
                    .clipShape(Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text("Verified Profiles Only")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundColor(AppTheme.textPrimary)
                    Text("Only show selfie-verified users")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundColor(AppTheme.textSecondary)
                }
                Spacer()
                Toggle("", isOn: $draft.preferences.verifiedOnly)
                    .tint(AppTheme.pink)
                    .labelsHidden()
            }
            .padding(16)
            .background(AppTheme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppTheme.pink.opacity(0.12), lineWidth: 1))
            .padding(.horizontal, 20)
        }
    }

    private var preferencesLinkSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionLabel("Dating Preferences")

            Button(action: { showPreferences = true }) {
                HStack(spacing: 12) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppTheme.primaryGradient)
                        .frame(width: 30, height: 30)
                        .background(AppTheme.pink.opacity(0.12))
                        .clipShape(Circle())

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Age, Height & Gender Filters")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundColor(AppTheme.textPrimary)
                        Text(preferencesSummary)
                            .font(.system(size: 12, design: .rounded))
                            .foregroundColor(AppTheme.textSecondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(AppTheme.textTertiary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(AppTheme.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppTheme.pink.opacity(0.12), lineWidth: 1))
                .padding(.horizontal, 20)
            }
            .buttonStyle(.plain)
        }
    }

    private var preferencesSummary: String {
        let prefs = draft.preferences
        var parts: [String] = []
        if !draft.lookingFor.isEmpty { parts.append(draft.lookingFor) }
        parts.append("Ages \(prefs.ageMin)–\(prefs.ageMax)")
        if !prefs.genders.isEmpty {
            parts.append(prefs.genders.joined(separator: ", "))
        } else {
            parts.append("Everyone")
        }
        if prefs.verifiedOnly { parts.append("Verified only") }
        return parts.joined(separator: " · ")
    }

    private var isCreatingProfile: Bool {
        switch mode {
        case .editing:
            return false
        case .creating:
            return true
        }
    }

    private var navigationTitleText: String {
        isCreatingProfile ? "Create Profile" : "Edit Profile"
    }

    private var submitButtonTitle: String {
        isCreatingProfile ? "Continue" : "Save"
    }

    private var canSubmit: Bool {
        guard isCreatingProfile else { return true }
        return !trimmedDraftName.isEmpty && !trimmedDraftBio.isEmpty && (18...99).contains(draft.age)
    }

    private var trimmedDraftName: String {
        draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedDraftBio: String {
        draft.bio.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func submitDraft() {
        let normalizedDraft = normalizedProfile(from: draft)
        profile = normalizedDraft
        onSave?(normalizedDraft)

        if !isCreatingProfile {
            dismiss()
        }
    }

    private func normalizedProfile(from profile: UserProfile) -> UserProfile {
        var profile = profile
        profile.name = profile.name.trimmingCharacters(in: .whitespacesAndNewlines)
        profile.bio = String(profile.bio.trimmingCharacters(in: .whitespacesAndNewlines).prefix(150))
        profile.profession = profile.profession.trimmingCharacters(in: .whitespacesAndNewlines)
        profile.prompts = profile.prompts.filter { !$0.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return profile
    }

    private func cmToFeet(_ cm: Int) -> String {
        let totalInches = Double(cm) / 2.54
        let feet = Int(totalInches) / 12
        let inches = Int(totalInches) % 12
        return "\(feet)'\(inches)\""
    }
}

// MARK: - TextField style helper
private extension View {
    func editFieldStyle() -> some View {
        self
            .font(.system(size: 15, design: .rounded))
            .foregroundColor(AppTheme.textPrimary)
            .multilineTextAlignment(.trailing)
            .tint(AppTheme.pink)
    }

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

private struct PhotoReorderDropDelegate: DropDelegate {
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

// MARK: - SliderField

private struct SliderField: View {
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
            // Header row
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

                // Value badge
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

            // Slider
            Slider(value: $value, in: range, step: step)
                .tint(AppTheme.pink)
                .padding(.horizontal, 16)

            // Range labels
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
