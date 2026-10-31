import SwiftUI

struct OnboardingVibeView: View {
    @Binding var draft: UserProfile
    let onBack: () -> Void
    let onNext: () -> Void

    @State private var editingPromptIndex: Int? = nil
    @State private var showPromptPicker = false
    @State private var showInterestPicker = false

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
                        promptsSection
                        interestsSection
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                    .padding(.bottom, 120)
                }
            }

            // MARK: Bottom Bar
            bottomBar
        }
        .sheet(isPresented: $showPromptPicker) {
            if let idx = editingPromptIndex, draft.prompts.indices.contains(idx) {
                PromptEditorView(prompt: $draft.prompts[idx])
            }
        }
        .sheet(isPresented: $showInterestPicker) {
            InterestPickerView(selected: $draft.interests)
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

            Spacer()

            VStack(spacing: 4) {
                Text("ClubMates")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(AppTheme.textPrimary)
                Text("Step 2 of 3")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(AppTheme.textSecondary)
            }

            Spacer()

            HStack(spacing: 4) {
                ForEach(0..<3) { i in
                    Capsule()
                        .fill(i < 2 ? AnyShapeStyle(AppTheme.primaryGradient) : AnyShapeStyle(AppTheme.textTertiary.opacity(0.45)))
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
                Image(systemName: "sparkles")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundColor(.white)
            }

            Text("Your Vibe")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(AppTheme.textPrimary)

            Text("Add a few prompts and pick interests. These help others spark a conversation with you.")
                .font(.system(size: 14, design: .rounded))
                .foregroundColor(AppTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(AppTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous))
    }

    // MARK: - Prompts Section

    private var promptsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Get to Know Me")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundColor(AppTheme.textPrimary)
                Spacer()
                if draft.prompts.count < 3 {
                    Button(action: addPrompt) {
                        Text("Add")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(AppTheme.primaryGradient)
                    }
                }
            }

            if draft.prompts.isEmpty {
                emptyPromptsCard
            } else {
                VStack(spacing: 10) {
                    ForEach(draft.prompts.indices, id: \.self) { idx in
                        promptRow(at: idx)
                    }
                }
            }

            Text("Add at least 1 prompt to continue.")
                .font(.system(size: 12, design: .rounded))
                .foregroundColor(draft.prompts.isEmpty ? AppTheme.pink.opacity(0.8) : AppTheme.textTertiary)
                .frame(maxWidth: .infinity, alignment: .center)
                .multilineTextAlignment(.center)
        }
    }

    private func promptRow(at idx: Int) -> some View {
        let prompt = draft.prompts[idx]
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(prompt.question.uppercased())
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .tracking(0.6)
                    .foregroundColor(AppTheme.pink)

                Text(prompt.answer.isEmpty ? "Tap to answer..." : prompt.answer)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundColor(prompt.answer.isEmpty ? AppTheme.textTertiary : AppTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 12) {
                Button(action: {
                    editingPromptIndex = idx
                    showPromptPicker = true
                }) {
                    Image(systemName: "pencil")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(AppTheme.textSecondary)
                }

                Button(action: {
                    draft.prompts.remove(at: idx)
                }) {
                    Image(systemName: "trash")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(AppTheme.red.opacity(0.7))
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(AppTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(AppTheme.pink.opacity(0.12), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onTapGesture {
            editingPromptIndex = idx
            showPromptPicker = true
        }
    }

    private var emptyPromptsCard: some View {
        VStack(spacing: 12) {
            Text("No prompts yet")
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundColor(AppTheme.textTertiary)

            Button(action: addPrompt) {
                Text("Add your first")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.primaryGradient)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .background(AppTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(style: StrokeStyle(lineWidth: 1.5, dash: [5]))
                .foregroundColor(AppTheme.textTertiary.opacity(0.4))
        )
    }

    private func addPrompt() {
        let question = PromptEditorView.questions.first ?? "Something I'm passionate about"
        draft.prompts.append(UserProfile.Prompt(question: question, answer: ""))
        editingPromptIndex = draft.prompts.count - 1
        showPromptPicker = true
    }

    // MARK: - Interests Section

    private var interestsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Interests")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundColor(AppTheme.textPrimary)
                Spacer()
                Button(action: { showInterestPicker = true }) {
                    HStack(spacing: 4) {
                        Image(systemName: draft.interests.isEmpty ? "plus" : "pencil")
                            .font(.system(size: 13, weight: .medium))
                        Text(draft.interests.isEmpty ? "Add" : "Edit")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(AppTheme.primaryGradient)
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                if draft.interests.isEmpty {
                    Button(action: { showInterestPicker = true }) {
                        HStack(spacing: 10) {
                            Image(systemName: "tag.fill")
                                .font(.system(size: 16))
                                .foregroundStyle(AppTheme.primaryGradient)
                            Text("Tap to pick your interests")
                                .font(.system(size: 14, design: .rounded))
                                .foregroundColor(AppTheme.textTertiary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(AppTheme.textTertiary)
                        }
                        .padding(16)
                        .background(AppTheme.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(style: StrokeStyle(lineWidth: 1.5, dash: [5]))
                                .foregroundColor(AppTheme.textTertiary.opacity(0.4))
                        )
                    }
                    .buttonStyle(.plain)
                } else {
                    FlowLayout(spacing: 8) {
                        ForEach(draft.interests, id: \.self) { interest in
                            HStack(spacing: 4) {
                                Text(interest)
                                    .font(.system(size: 13, weight: .medium, design: .rounded))
                                    .foregroundColor(AppTheme.textPrimary)
                                Button(action: { draft.interests.removeAll { $0 == interest } }) {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundColor(AppTheme.textSecondary)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(AppTheme.surface)
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(AppTheme.pink.opacity(0.15), lineWidth: 1))
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppTheme.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(AppTheme.pink.opacity(0.12), lineWidth: 1))
                }
            }

            let needed = max(0, 3 - draft.interests.count)
            Text(needed == 0 ? "✓ Great selection!" : "Select \(needed) more interest\(needed == 1 ? "" : "s") to continue.")
                .font(.system(size: 12, design: .rounded))
                .foregroundColor(needed == 0 ? AppTheme.green : AppTheme.pink.opacity(0.8))
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    // MARK: - Bottom Bar

    private var canContinue: Bool {
        !draft.prompts.isEmpty && draft.interests.count >= 3
    }

    private var bottomBar: some View {
        VStack(spacing: 0) {
            Divider()
                .background(AppTheme.surface)
            Button(action: { if canContinue { onNext() } }) {
                Text("Continue")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(canContinue ? AnyShapeStyle(AppTheme.primaryGradient) : AnyShapeStyle(AppTheme.surface))
                    .clipShape(Capsule())
            }
            .disabled(!canContinue)
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 16)
        }
        .background(AppTheme.background)
    }
}
