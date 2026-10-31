import SwiftUI

struct PromptEditorView: View {
    @Binding var prompt: UserProfile.Prompt
    @Environment(\.dismiss) private var dismiss

    @State private var selectedQuestion: String
    @State private var answer: String
    @State private var showQuestionPicker = false

    init(prompt: Binding<UserProfile.Prompt>) {
        self._prompt = prompt
        self._selectedQuestion = State(initialValue: prompt.wrappedValue.question)
        self._answer = State(initialValue: prompt.wrappedValue.answer)
    }

    static let questions = [
        "The way to my heart is...",
        "I'm looking for...",
        "My love language is...",
        "A fact about me that surprises people...",
        "My ideal Sunday...",
        "I'll know it's a match if...",
        "I get too excited about...",
        "My biggest green flag...",
        "Change my mind that...",
        "Two truths and a lie...",
        "My most irrational fear...",
        "I guarantee we'll get along if...",
        "The key to my heart...",
        "Unusual skill I have...",
        "Weirdly, I'm good at...",
        "First round is on me if...",
        "My go-to karaoke song is...",
        "I'm convinced that...",
        "Hot take: ...",
        "My simple pleasures are...",
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.background.ignoresSafeArea()

                VStack(spacing: 0) {
                    // Question selector
                    Button(action: { showQuestionPicker = true }) {
                        HStack {
                            Text(selectedQuestion)
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundColor(AppTheme.pink)
                                .textCase(.uppercase)
                                .tracking(0.5)
                                .multilineTextAlignment(.leading)
                            Spacer()
                            Image(systemName: "chevron.down")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(AppTheme.textSecondary)
                        }
                        .padding(18)
                        .background(AppTheme.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(AppTheme.pink.opacity(0.25), lineWidth: 1)
                        )
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 24)

                    // Answer input
                    ZStack(alignment: .topLeading) {
                        if answer.isEmpty {
                            Text("Write your answer...")
                                .font(.system(size: 17, design: .rounded))
                                .foregroundColor(AppTheme.textTertiary)
                                .padding(18)
                        }
                        TextEditor(text: $answer)
                            .font(.system(size: 17, weight: .medium, design: .rounded))
                            .foregroundColor(AppTheme.textPrimary)
                            .scrollContentBackground(.hidden)
                            .padding(14)
                            .frame(minHeight: 130, maxHeight: 200)
                    }
                    .background(AppTheme.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal, 20)
                    .padding(.top, 14)

                    HStack {
                        Spacer()
                        Text("\(answer.count)/150")
                            .font(.system(size: 12, design: .rounded))
                            .foregroundColor(answer.count > 150 ? AppTheme.red : AppTheme.textTertiary)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 6)

                    // Preview card
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Preview")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundColor(AppTheme.textTertiary)
                            .textCase(.uppercase)
                            .tracking(0.8)

                        VStack(alignment: .leading, spacing: 8) {
                            Text(selectedQuestion)
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundColor(AppTheme.pink)
                                .textCase(.uppercase)
                                .tracking(0.6)
                            Text(answer.isEmpty ? "Your answer will appear here" : answer)
                                .font(.system(size: 16, weight: .medium, design: .rounded))
                                .foregroundColor(answer.isEmpty ? AppTheme.textTertiary : AppTheme.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(18)
                        .background(AppTheme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppTheme.pink.opacity(0.15), lineWidth: 1))
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 28)

                    Spacer()
                }
            }
            .navigationTitle("Edit Prompt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(AppTheme.cardBackground, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(AppTheme.textSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    let canSave = !answer.trimmingCharacters(in: .whitespaces).isEmpty
                    Button("Done") {
                        prompt = UserProfile.Prompt(question: selectedQuestion, answer: answer.trimmingCharacters(in: .whitespacesAndNewlines))
                        dismiss()
                    }
                    .foregroundStyle(canSave ? AnyShapeStyle(AppTheme.primaryGradient) : AnyShapeStyle(Color(AppTheme.textTertiary)))
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .disabled(!canSave)
                }
            }
            .sheet(isPresented: $showQuestionPicker) {
                QuestionPickerView(selected: $selectedQuestion)
            }
        }
    }
}

// MARK: - Question picker sheet
struct QuestionPickerView: View {
    @Binding var selected: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.background.ignoresSafeArea()

                List {
                    ForEach(PromptEditorView.questions, id: \.self) { question in
                        Button(action: {
                            selected = question
                            dismiss()
                        }) {
                            HStack {
                                Text(question)
                                    .font(.system(size: 15, design: .rounded))
                                    .foregroundColor(AppTheme.textPrimary)
                                Spacer()
                                if question == selected {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(AppTheme.primaryGradient)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .listRowBackground(AppTheme.cardBackground)
                        .listRowSeparatorTint(AppTheme.surface)
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Choose a prompt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(AppTheme.cardBackground, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(AppTheme.primaryGradient)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
