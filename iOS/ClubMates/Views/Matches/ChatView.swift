import SwiftUI

struct ChatView: View {
    let match: Match
    @ObservedObject var viewModel: MatchesViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var showUnmatchConfirmation = false
    @State private var showSOSConfirmation = false
    @State private var showBlockConfirmation = false
    @State private var showSpamReasons = false
    @FocusState private var isInputFocused: Bool

    private let spamReasons = [
        "Promotional or selling",
        "Scam or money request",
        "Fake or suspicious profile",
        "Repeated unwanted messages",
        "Harassment or sexual spam"
    ]

    private var isMatchUserOnline: Bool {
        viewModel.isUserOnline(match.profile.id)
    }

    var body: some View {
        ZStack {
            AppTheme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                chatHeader
                messageList
                    .onTapGesture { isInputFocused = false }
                inputBar
            }

            if showSOSConfirmation {
                sosOverlay
                    .transition(.opacity)
                    .zIndex(300)
            }

            if viewModel.sosError != nil {
                sosErrorOverlay
                    .transition(.opacity)
                    .zIndex(300)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: showSOSConfirmation)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: viewModel.sosError)
        .toolbar(.hidden, for: .navigationBar)
        .confirmationDialog(
            "Unmatch \(match.profile.name)?",
            isPresented: $showUnmatchConfirmation,
            titleVisibility: .visible
        ) {
            Button("Unmatch", role: .destructive) {
                let impact = UIImpactFeedbackGenerator(style: .medium)
                impact.impactOccurred()
                viewModel.unmatch(match)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the conversation and chat history from Matches.")
        }
        .confirmationDialog(
            "Block \(match.profile.name)?",
            isPresented: $showBlockConfirmation,
            titleVisibility: .visible
        ) {
            Button("Block", role: .destructive) {
                blockMatch()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("They will disappear from your matches and will not be shown to you again.")
        }
        .confirmationDialog(
            "Why is this spam?",
            isPresented: $showSpamReasons,
            titleVisibility: .visible
        ) {
            ForEach(spamReasons, id: \.self) { reason in
                Button(reason, role: .destructive) {
                    reportSpam(reason: reason)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your selected reason will be saved with the report.")
        }
        .alert(
            "Message not sent",
            isPresented: Binding(
                get: { viewModel.messageError != nil },
                set: { if !$0 { viewModel.messageError = nil } }
            )
        ) {
            Button("OK", role: .cancel) {
                viewModel.messageError = nil
            }
        } message: {
            Text(viewModel.messageError ?? "Please try again.")
        }
        .alert(
            "Safety action failed",
            isPresented: Binding(
                get: { viewModel.safetyError != nil },
                set: { if !$0 { viewModel.safetyError = nil } }
            )
        ) {
            Button("OK", role: .cancel) {
                viewModel.safetyError = nil
            }
        } message: {
            Text(viewModel.safetyError ?? "Please try again.")
        }
    }

    // MARK: - Header

    private var chatHeader: some View {
        HStack(spacing: 12) {
            Button(action: { dismiss() }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(AppTheme.textPrimary)
                    .frame(width: 36, height: 36)
            }

            ProfileAvatar(profile: match.profile, size: 42)
                .overlay(Circle().stroke(AppTheme.primaryGradient, lineWidth: 2))

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(match.profile.name)
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundColor(AppTheme.textPrimary)
                    if match.profile.isVerified {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(AppTheme.primaryGradient)
                    }
                }
                HStack(spacing: 4) {
                    Circle()
                        .fill(isMatchUserOnline ? AppTheme.green : AppTheme.textSecondary.opacity(0.65))
                        .frame(width: 7, height: 7)
                    Text(isMatchUserOnline ? "Active now" : "Offline")
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                        .foregroundColor(isMatchUserOnline ? AppTheme.green : AppTheme.textSecondary)
                }
            }

            Spacer()

            Menu {
                Button(role: .destructive) {
                    showSOSConfirmation = true
                } label: {
                    Label("Emergency SOS", systemImage: "exclamationmark.triangle.fill")
                }

                Button(role: .destructive) {
                    showSpamReasons = true
                } label: {
                    Label("Report spam", systemImage: "flag.fill")
                }

                Button(role: .destructive) {
                    showBlockConfirmation = true
                } label: {
                    Label("Block", systemImage: "hand.raised.fill")
                }

                Button(role: .destructive) {
                    showUnmatchConfirmation = true
                } label: {
                    Label("Unmatch", systemImage: "person.crop.circle.badge.xmark")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(AppTheme.textPrimary)
                    .frame(width: 36, height: 36)
                    .background(AppTheme.surface)
                    .clipShape(Circle())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            AppTheme.cardBackground
                .overlay(Rectangle().frame(height: 1).foregroundColor(AppTheme.surface), alignment: .bottom)
        )
    }

    // MARK: - Message List

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    matchBanner

                    ForEach(viewModel.messages) { message in
                        let msgs = viewModel.messages
                        let index = msgs.firstIndex(where: { $0.id == message.id }) ?? 0
                        let prev = index > 0 ? msgs[index - 1] : nil
                        let next = index < msgs.count - 1 ? msgs[index + 1] : nil
                        MessageBubble(
                            message: message,
                            isFirstInGroup: prev?.isFromMe != message.isFromMe,
                            isLastInGroup: next?.isFromMe != message.isFromMe
                        )
                        .id(message.id)
                    }

                    if viewModel.isTyping {
                        TypingIndicator()
                            .id("typing")
                            .transition(.asymmetric(insertion: .push(from: .bottom), removal: .opacity))
                    }

                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: viewModel.messages.count) {
                withAnimation(.spring(response: 0.35)) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
            .onChange(of: viewModel.isTyping) {
                if viewModel.isTyping {
                    withAnimation(.spring(response: 0.35)) {
                        proxy.scrollTo("typing", anchor: .bottom)
                    }
                }
            }
        }
    }

    private var matchBanner: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(AppTheme.pink.opacity(0.12))
                    .frame(width: 88, height: 88)
                ProfileAvatar(profile: match.profile, size: 72)
                    .overlay(Circle().stroke(AppTheme.primaryGradient, lineWidth: 2.5))
            }
            VStack(spacing: 4) {
                Text("You matched with \(match.profile.name)!")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(AppTheme.textPrimary)
                Text("Say something nice ✨")
                    .font(.system(size: 13, design: .rounded))
                    .foregroundColor(AppTheme.textSecondary)
            }
        }
        .padding(.vertical, 28)
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        HStack(spacing: 10) {
            HStack {
                TextField("Message...", text: $viewModel.newMessageText, axis: .vertical)
                    .font(.system(size: 16, design: .rounded))
                    .foregroundColor(AppTheme.textPrimary)
                    .lineLimit(1...5)
                    .focused($isInputFocused)
                    .submitLabel(.send)
                    .onSubmit { viewModel.sendMessage() }
                    .tint(AppTheme.pink)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .background(AppTheme.surface)
            .clipShape(Capsule())

            Button(action: {
                let impact = UIImpactFeedbackGenerator(style: .light)
                impact.impactOccurred()
                viewModel.sendMessage()
            }) {
                Image(systemName: viewModel.newMessageText.trimmingCharacters(in: .whitespaces).isEmpty ? "mic.fill" : "paperplane.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 46, height: 46)
                    .background(
                        viewModel.newMessageText.trimmingCharacters(in: .whitespaces).isEmpty
                            ? AnyShapeStyle(AppTheme.surface)
                            : AnyShapeStyle(AppTheme.primaryGradient)
                    )
                    .clipShape(Circle())
                    .scaleEffect(viewModel.newMessageText.trimmingCharacters(in: .whitespaces).isEmpty ? 1 : 1.05)
                    .animation(.spring(response: 0.25, dampingFraction: 0.6), value: viewModel.newMessageText.isEmpty)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            AppTheme.cardBackground
                .overlay(Rectangle().frame(height: 1).foregroundColor(AppTheme.surface), alignment: .top)
        )
    }

    private var sosOverlay: some View {
        ZStack {
            Color.black.opacity(0.7)
                .ignoresSafeArea()
                .onTapGesture { showSOSConfirmation = false }

            VStack(spacing: 0) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(colors: [AppTheme.red, Color(hex: "B91C1C")], startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .frame(width: 64, height: 64)
                        .shadow(color: AppTheme.red.opacity(0.45), radius: 16, x: 0, y: 6)
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundColor(.white)
                }
                .padding(.top, 32)

                Text("Emergency SOS")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(AppTheme.textPrimary)
                    .padding(.top, 20)

                Text("This records this chat as safety context and opens the emergency phone number.")
                    .font(.system(size: 15, weight: .regular, design: .rounded))
                    .foregroundColor(AppTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.top, 8)

                VStack(spacing: 12) {
                    Button {
                        triggerEmergencySOS()
                        showSOSConfirmation = false
                    } label: {
                        Text("Record SOS & Call 112")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(AppTheme.primaryGradient)
                            .clipShape(Capsule())
                            .shadow(color: AppTheme.pink.opacity(0.35), radius: 12, x: 0, y: 5)
                    }
                    .buttonStyle(BounceButtonStyle())

                    Button {
                        showSOSConfirmation = false
                    } label: {
                        Text("Cancel")
                            .font(.system(size: 16, weight: .medium, design: .rounded))
                            .foregroundColor(AppTheme.textSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(AppTheme.surface)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(BounceButtonStyle())
                }
                .padding(.horizontal, 24)
                .padding(.top, 28)
                .padding(.bottom, 28)
            }
            .background(
                RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous)
                    .fill(AppTheme.cardBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.12), AppTheme.red.opacity(0.2), Color.white.opacity(0.06)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous))
            .shadow(color: .black.opacity(0.4), radius: 24, x: 0, y: 12)
            .shadow(color: AppTheme.red.opacity(0.08), radius: 12, x: 0, y: 4)
            .padding(.horizontal, 32)
            .transition(.scale(scale: 0.9).combined(with: .opacity))
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.72), value: showSOSConfirmation)
    }

    private var sosErrorOverlay: some View {
        ZStack {
            Color.black.opacity(0.7)
                .ignoresSafeArea()
                .onTapGesture { viewModel.sosError = nil }

            VStack(spacing: 0) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(colors: [AppTheme.red, Color(hex: "B91C1C")], startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .frame(width: 64, height: 64)
                        .shadow(color: AppTheme.red.opacity(0.45), radius: 16, x: 0, y: 6)
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundColor(.white)
                }
                .padding(.top, 32)

                Text("SOS Could Not Be Recorded")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(AppTheme.textPrimary)
                    .padding(.top, 20)

                Text(viewModel.sosError ?? "Call 112 directly if you are in immediate danger.")
                    .font(.system(size: 15, weight: .regular, design: .rounded))
                    .foregroundColor(AppTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.top, 8)

                Button {
                    viewModel.sosError = nil
                } label: {
                    Text("OK")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(AppTheme.primaryGradient)
                        .clipShape(Capsule())
                        .shadow(color: AppTheme.pink.opacity(0.35), radius: 12, x: 0, y: 5)
                }
                .buttonStyle(BounceButtonStyle())
                .padding(.horizontal, 24)
                .padding(.top, 28)
                .padding(.bottom, 28)
            }
            .background(
                RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous)
                    .fill(AppTheme.cardBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.12), AppTheme.red.opacity(0.2), Color.white.opacity(0.06)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous))
            .shadow(color: .black.opacity(0.4), radius: 24, x: 0, y: 12)
            .shadow(color: AppTheme.red.opacity(0.08), radius: 12, x: 0, y: 4)
            .padding(.horizontal, 32)
            .transition(.scale(scale: 0.9).combined(with: .opacity))
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.72), value: viewModel.sosError)
    }

    private func triggerEmergencySOS() {
        let notification = UINotificationFeedbackGenerator()
        notification.notificationOccurred(.warning)

        Task {
            await viewModel.triggerSOS(for: match)
        }

        if let url = URL(string: "tel://112") {
            openURL(url)
        }
    }

    private func blockMatch() {
        let impact = UIImpactFeedbackGenerator(style: .medium)
        impact.impactOccurred()

        Task {
            if await viewModel.block(match) {
                dismiss()
            }
        }
    }

    private func reportSpam(reason: String) {
        let impact = UIImpactFeedbackGenerator(style: .medium)
        impact.impactOccurred()

        Task {
            if await viewModel.reportSpam(match, reason: reason) {
                dismiss()
            }
        }
    }
}

// MARK: - Message Bubble

struct MessageBubble: View {
    let message: ChatMessage
    var isFirstInGroup: Bool = true
    var isLastInGroup: Bool = true

    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            if message.isFromMe {
                Spacer(minLength: 56)
            }

            VStack(alignment: message.isFromMe ? .trailing : .leading, spacing: 2) {
                Text(message.text)
                    .font(.system(size: 16, design: .rounded))
                    .foregroundColor(message.isFromMe ? .white : AppTheme.textPrimary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        message.isFromMe
                            ? AnyShapeStyle(AppTheme.primaryGradient)
                            : AnyShapeStyle(AppTheme.surface)
                    )
                    .clipShape(BubbleShape(isFromMe: message.isFromMe, isFirst: isFirstInGroup, isLast: isLastInGroup))

                if isLastInGroup {
                    Text(message.timestamp, style: .time)
                        .font(.system(size: 11, design: .rounded))
                        .foregroundColor(AppTheme.textTertiary)
                        .padding(message.isFromMe ? .trailing : .leading, 4)
                }
            }

            if !message.isFromMe {
                Spacer(minLength: 56)
            }
        }
        .padding(.vertical, isLastInGroup ? 3 : 1)
    }
}

// MARK: - Typing Indicator

struct TypingIndicator: View {
    @State private var animating = false

    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(AppTheme.textSecondary)
                        .frame(width: 7, height: 7)
                        .scaleEffect(animating ? 1.4 : 1.0)
                        .animation(
                            .easeInOut(duration: 0.45)
                                .repeatForever(autoreverses: true)
                                .delay(Double(i) * 0.18),
                            value: animating
                        )
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(AppTheme.surface)
            .clipShape(Capsule())

            Spacer(minLength: 56)
        }
        .onAppear { animating = true }
    }
}

// MARK: - Bubble Shape

struct BubbleShape: Shape {
    var isFromMe: Bool
    var isFirst: Bool
    var isLast: Bool

    func path(in rect: CGRect) -> Path {
        let r: CGFloat = 18
        let smallR: CGFloat = 5
        var path = Path()

        let tl = isFromMe ? r : (isFirst ? r : smallR)
        let tr = isFromMe ? (isFirst ? r : smallR) : r
        let bl = isFromMe ? r : (isLast ? r : smallR)
        let br = isFromMe ? (isLast ? r : smallR) : r

        path.move(to: CGPoint(x: rect.minX + tl, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - tr, y: rect.minY))
        path.addArc(center: CGPoint(x: rect.maxX - tr, y: rect.minY + tr), radius: tr, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - br))
        path.addArc(center: CGPoint(x: rect.maxX - br, y: rect.maxY - br), radius: br, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        path.addLine(to: CGPoint(x: rect.minX + bl, y: rect.maxY))
        path.addArc(center: CGPoint(x: rect.minX + bl, y: rect.maxY - bl), radius: bl, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + tl))
        path.addArc(center: CGPoint(x: rect.minX + tl, y: rect.minY + tl), radius: tl, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        path.closeSubpath()
        return path
    }
}
