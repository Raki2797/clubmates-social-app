import SwiftUI

enum AuthIntent: Hashable, Identifiable {
    case login
    case createAccount

    var id: Self { self }
}

struct AuthenticationFlowView: View {
    @EnvironmentObject private var session: AppSessionStore
    @Environment(\.dismiss) private var dismiss

    @State private var intent: AuthIntent

    @State private var phoneNumber = ""
    @State private var otpCode = ""
    @State private var step: Step = .phoneNumber
    @State private var localErrorMessage: String?
    @State private var showAccountExistsAlert = false
    @State private var deletionScheduledAt: Date?
    @State private var isRestoringDeletedAccount = false
    @FocusState private var focusedField: Field?

    init(intent: AuthIntent) {
        _intent = State(initialValue: intent)
    }

    enum Step {
        case phoneNumber
        case otp
    }

    enum Field {
        case phoneNumber
        case otp
    }

    var body: some View {
        ZStack {
            AppTheme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                header

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 24) {
                        heroCard
                        inputCard
                        buildNoteCard
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                    .padding(.bottom, 40)
                }

                continueButton
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 16)
                    .background(AppTheme.background)
            }

            if showAccountExistsAlert {
                accountExistsOverlay
            }
        }
        .navigationBarBackButtonHidden(true)
        .onAppear {
            DispatchQueue.main.async {
                focusedField = .phoneNumber
            }
        }
        .onChange(of: otpCode) { _, newValue in
            otpCode = String(newValue.filter(\.isNumber).prefix(6))
        }
        .onChange(of: phoneNumber) { _, newValue in
            let normalized = normalizedPhoneEntry(from: newValue)
            if normalized != newValue {
                phoneNumber = normalized
            }
            deletionScheduledAt = nil
            isRestoringDeletedAccount = false
            if normalized.filter(\.isNumber).count == 10 {
                focusedField = nil
            }
        }
    }

    private var accountExistsOverlay: some View {
        ZStack {
            Color.black.opacity(0.7)
                .ignoresSafeArea()
                .onTapGesture { showAccountExistsAlert = false }

            VStack(spacing: 0) {
                ZStack {
                    Circle()
                        .fill(AppTheme.primaryGradient)
                        .frame(width: 64, height: 64)
                        .shadow(color: AppTheme.purple.opacity(0.4), radius: 16, x: 0, y: 6)
                    Image(systemName: "person.badge.clock.fill")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundColor(.white)
                }
                .padding(.top, 32)

                Text("Already a Member?")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(AppTheme.textPrimary)
                    .padding(.top, 20)

                Text("An account with **\(formattedPhoneNumber)** already exists.")
                    .font(.system(size: 15, weight: .regular, design: .rounded))
                    .foregroundColor(AppTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.top, 8)

                Text("Would you like to log in instead?")
                    .font(.system(size: 15, weight: .regular, design: .rounded))
                    .foregroundColor(AppTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.top, 2)

                VStack(spacing: 12) {
                    Button {
                        showAccountExistsAlert = false
                        intent = .login
                        step = .otp
                        DispatchQueue.main.async { focusedField = .otp }
                    } label: {
                        Text("Log In Instead")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(AppTheme.primaryGradient)
                            .clipShape(Capsule())
                            .shadow(color: AppTheme.purple.opacity(0.35), radius: 12, x: 0, y: 5)
                    }
                    .buttonStyle(BounceButtonStyle())

                    Button { showAccountExistsAlert = false } label: {
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
                                    colors: [Color.white.opacity(0.12), AppTheme.purple.opacity(0.2), Color.white.opacity(0.06)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous))
            .shadow(color: .black.opacity(0.4), radius: 24, x: 0, y: 12)
            .shadow(color: AppTheme.purple.opacity(0.08), radius: 12, x: 0, y: 4)
            .padding(.horizontal, 32)
            .transition(.scale(scale: 0.9).combined(with: .opacity))
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.72), value: showAccountExistsAlert)
    }

    private var header: some View {
        HStack {
            Button(action: step == .otp ? goBackToPhoneNumber : { dismiss() }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(AppTheme.textPrimary)
                    .frame(width: 42, height: 42)
                    .background(AppTheme.surface)
                    .clipShape(Circle())
            }

            Spacer()

            VStack(spacing: 2) {
                Text("ClubMates")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(AppTheme.textPrimary)
                Text(step == .phoneNumber
                    ? (intent == .login ? "Log In" : "Create Account")
                    : "Verification"
                )
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(AppTheme.textSecondary)
            }

            Spacer()

            progressPills
                .frame(width: 42, height: 42)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    private var heroCard: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(hex: "24103D"), Color(hex: "571A53"), Color(hex: "8D2D63")],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Circle()
                .fill(Color.white.opacity(0.08))
                .frame(width: 220, height: 220)
                .offset(x: 120, y: -90)

            Circle()
                .fill(Color.white.opacity(0.05))
                .frame(width: 140, height: 140)
                .offset(x: -30, y: -100)

            VStack(alignment: .leading, spacing: 14) {
                Text(step == .phoneNumber ? (intent == .login ? "Welcome Back" : "Get Started") : "One More Step")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.75))
                    .textCase(.uppercase)
                    .tracking(1)

                Text(step == .phoneNumber
                    ? (intent == .login ? "Sign back in." : "Create your account.")
                    : "Enter your verification code."
                )
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundColor(.white)

                Text(step == .phoneNumber
                    ? (intent == .login
                        ? "Enter your phone number to log back in to ClubMates."
                        : "Enter your phone number to get started. You'll set up your profile next.")
                    : "Type the 6-digit SMS code to continue."
                )
                .font(.system(size: 14, design: .rounded))
                .foregroundColor(.white.opacity(0.78))
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(24)
        }
        .frame(height: 250)
    }

    private var inputCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(step == .phoneNumber ? "Mobile Number" : "Verification Code")
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundColor(AppTheme.textPrimary)

            Text(step == .phoneNumber
                ? "Enter your number to continue. We default to India with +91."
                : "Enter the 6-digit code to continue with \(formattedPhoneNumber)."
            )
            .font(.system(size: 13, design: .rounded))
            .foregroundColor(AppTheme.textSecondary)

            if step == .phoneNumber {
                phoneNumberField
                if deletionScheduledAt != nil {
                    restoreNoticeCard
                }
            } else {
                otpField
            }

            if step == .otp {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle.fill")
                        .foregroundColor(AppTheme.textSecondary)
                    Text("We sent a 6-digit SMS code to \(formattedPhoneNumber).")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(AppTheme.textSecondary)
                }
            }

            if let errorMessage = localErrorMessage ?? session.authErrorMessage {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(AppTheme.red)
                    Text(errorMessage)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(AppTheme.red)
                }
            }
        }
        .padding(20)
        .background(AppTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
    }

    private var buildNoteCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AppTheme.primaryGradient)
                    .frame(width: 34, height: 34)
                    .background(AppTheme.surface)
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text("SMS Verification")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundColor(AppTheme.textPrimary)

                    Text(step == .phoneNumber
                        ? "We will send a 6-digit login code to this number."
                        : "Codes usually arrive within a few seconds. If yours does not arrive, go back and request a new one."
                    )
                        .font(.system(size: 13, design: .rounded))
                        .foregroundColor(AppTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(AppTheme.surface.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var phoneNumberField: some View {
        HStack(spacing: 14) {
            Image(systemName: "iphone")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(AppTheme.primaryGradient)
                .frame(width: 20)

            Rectangle()
                .fill(AppTheme.surface)
                .frame(width: 1, height: 28)

            Text("+91")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(AppTheme.textPrimary)

            TextField("98765 43210", text: $phoneNumber)
                .keyboardType(.phonePad)
                .textContentType(.telephoneNumber)
                .focused($focusedField, equals: .phoneNumber)
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundColor(AppTheme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 18)
        .background(AppTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(AppTheme.surface, lineWidth: 1)
        )
    }

    private var otpField: some View {
        HStack(spacing: 14) {
            Image(systemName: "number")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(AppTheme.primaryGradient)
                .frame(width: 20)

            Rectangle()
                .fill(AppTheme.surface)
                .frame(width: 1, height: 28)

            TextField("000000", text: $otpCode)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .focused($focusedField, equals: .otp)
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundColor(AppTheme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 18)
        .background(AppTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(AppTheme.surface, lineWidth: 1)
        )
    }

    private var continueButton: some View {
        Button(action: handlePrimaryAction) {
            Text(session.isNetworkBusy ? "Please wait..." : primaryButtonTitle)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(canContinue ? AnyShapeStyle(AppTheme.primaryGradient) : AnyShapeStyle(AppTheme.surface))
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!canContinue || session.isNetworkBusy)
    }

    private var restoreNoticeCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "arrow.counterclockwise.circle.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(AppTheme.primaryGradient)
                .frame(width: 34, height: 34)
                .background(AppTheme.surface)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 5) {
                Text("Account deletion is pending")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(AppTheme.textPrimary)

                Text("Restore this account before \(formattedDeletionDate) to keep your profile and chats.")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(AppTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .background(AppTheme.pink.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(AppTheme.pink.opacity(0.22), lineWidth: 1)
        )
    }

    private var progressPills: some View {
        HStack(spacing: 4) {
            pill(active: true)
            pill(active: step == .otp)
        }
    }

    private func pill(active: Bool) -> some View {
        Capsule()
            .fill(active ? AppTheme.pink : AppTheme.textTertiary.opacity(0.45))
            .frame(width: 16, height: 6)
    }

    private var canContinue: Bool {
        switch step {
        case .phoneNumber:
            return trimmedPhoneNumber.filter(\.isNumber).count == 10
        case .otp:
            return otpCode.count == 6
        }
    }

    private var primaryButtonTitle: String {
        switch step {
        case .phoneNumber:
            return deletionScheduledAt == nil ? "Continue" : "Restore Account"
        case .otp:
            return isRestoringDeletedAccount ? "Verify And Restore" : "Verify And Continue"
        }
    }

    private var formattedDeletionDate: String {
        guard let deletionScheduledAt else { return "the deletion window ends" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: deletionScheduledAt)
    }

    private var formattedPhoneNumber: String {
        trimmedPhoneNumber.isEmpty ? "+91" : "+91\(trimmedPhoneNumber.filter(\.isNumber))"
    }

    private var trimmedPhoneNumber: String {
        phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func handlePrimaryAction() {
        switch step {
        case .phoneNumber:
            Task {
                localErrorMessage = nil
                if deletionScheduledAt != nil {
                    let (success, _) = await session.sendOTP(phoneNumber: formattedPhoneNumber, restore: true)
                    guard success else { return }
                    isRestoringDeletedAccount = true
                    step = .otp
                    DispatchQueue.main.async {
                        focusedField = .otp
                    }
                    return
                }

                guard let status = await session.accountStatus(phoneNumber: formattedPhoneNumber) else {
                    localErrorMessage = session.authErrorMessage
                    return
                }

                if let scheduledAt = status.deletionScheduledAt {
                    deletionScheduledAt = scheduledAt
                    localErrorMessage = nil
                    return
                }

                let (success, userExists) = await session.sendOTP(phoneNumber: formattedPhoneNumber)
                guard success else { return }
                // On create-account flow, intercept before OTP if the number is already registered
                if intent == .createAccount && userExists == true {
                    showAccountExistsAlert = true
                    return
                }
                step = .otp
                DispatchQueue.main.async {
                    focusedField = .otp
                }
            }
        case .otp:
            focusedField = nil
            Task {
                localErrorMessage = nil
                let verified = await session.verifyOTP(
                    phoneNumber: formattedPhoneNumber,
                    code: otpCode,
                    restore: isRestoringDeletedAccount
                )
                if !verified {
                    localErrorMessage = session.authErrorMessage
                }
            }
        }
    }

    private func goBackToPhoneNumber() {
        step = .phoneNumber
        otpCode = ""
        isRestoringDeletedAccount = false
        DispatchQueue.main.async {
            focusedField = .phoneNumber
        }
    }

    private func normalizedPhoneEntry(from value: String) -> String {
        let strippedCountryCode = value
            .replacingOccurrences(of: "+91", with: "")
            .replacingOccurrences(of: "+", with: "")

        let digits = strippedCountryCode.filter(\.isNumber)
        return String(digits.prefix(10))
    }
}

struct ProfileCreationView: View {
    @EnvironmentObject private var session: AppSessionStore
    @State private var draft = UserProfile(
        name: "",
        age: 21,
        bio: "",
        distance: 0,
        prompts: [],
        photos: [],
        interests: [],
        profession: "Student",
        gender: "Male",
        height: 170,
        isVerified: false,
        lookingFor: "",
        preferences: .default
    )

    var body: some View {
        EditProfileView(
            profile: $draft,
            mode: .creating,
            onSave: { session.completeProfile($0) },
            onCancel: { session.signOut() }
        )
    }
}
