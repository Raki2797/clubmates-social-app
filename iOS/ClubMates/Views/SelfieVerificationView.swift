import SwiftUI
import AVFoundation
import Vision

struct SelfieVerificationView: View {
    @EnvironmentObject private var session: AppSessionStore
    @Environment(\.tabBarState) private var tabBarState

    /// When non-nil the view was presented as a sheet from ProfileView.
    /// Called after successful upload so the sheet can be dismissed.
    var onComplete: (() -> Void)? = nil

    @StateObject private var camera = CameraManager()

    @State private var verificationStep: VerificationStep = .intro
    @State private var capturedPhoto: UIImage? = nil
    @State private var blinkDetected = false
    @State private var blinkPulse = false
    @State private var uploadPulse = false
    @State private var verificationFailed = false
    @State private var blinkTimedOut = false
    @State private var blinkTimeoutTask: Task<Void, Never>? = nil
    @State private var permissionDenied = false

    enum VerificationStep: Equatable {
        case intro               // Pre-camera instructions screen
        case takePhoto           // Step 1: position face and tap capture
        case livenessCheck       // Step 2: blink to confirm liveness
        case uploading
        case pendingVerification
        case failed(mismatchedPhotoIds: [String])
        case done
    }

    var body: some View {
        ZStack {
            if verificationStep == .intro {
                introScreen
                    .transition(.opacity)
            } else {
                cameraScreen
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: verificationStep == .intro)
        .ignoresSafeArea()
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    onComplete?()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .semibold))
                        Text("Back")
                            .font(.system(size: 16, weight: .medium))
                    }
                    .foregroundColor(.white)
                }
            }
        }
        .toolbarBackground(.hidden, for: .navigationBar)
        .background(SwipeBackEnabler())
        .onAppear { tabBarState?.isHidden = true }
        .onDisappear {
            camera.teardown()
            tabBarState?.isHidden = false
        }
        .onChange(of: camera.capturedImage) { _, image in
            guard let image else { return }
            capturedPhoto = image
            if verificationStep == .takePhoto {
                verificationStep = .livenessCheck
                blinkTimedOut = false
                camera.startBlinkDetection()
                blinkTimeoutTask?.cancel()
                blinkTimeoutTask = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 15_000_000_000)
                    guard !Task.isCancelled, verificationStep == .livenessCheck, !blinkDetected else { return }
                    blinkTimedOut = true
                }
            }
        }
        .onChange(of: camera.blinkDetected) { _, detected in
            guard detected, verificationStep == .livenessCheck else { return }
            blinkTimeoutTask?.cancel()
            blinkDetected = true
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 800_000_000)
                guard let photo = capturedPhoto,
                      let jpeg = photo.resizedForVerification()?.jpegData(compressionQuality: 0.95)
                               ?? photo.jpegData(compressionQuality: 0.92) else {
                    restartVerificationCapture()
                    return
                }

                verificationStep = .uploading

                #if DEBUG
                UIImageWriteToSavedPhotosAlbum(photo, nil, nil, nil)
                #endif

                do {
                    try await session.uploadVerificationSelfie(jpeg)
                } catch {
                    restartVerificationCapture()
                    return
                }

                // Upload succeeded — backend processes the embedding asynchronously.
                // Dismiss immediately; verification result will arrive via WebSocket
                // or on next profile refresh.
                verificationStep = .done
                onComplete?()
            }
        }
    }

    private let bottomPanelHeight: CGFloat = 290

    @MainActor
    private func restartVerificationCapture() {
        blinkTimeoutTask?.cancel()
        blinkTimedOut = false
        verificationStep = .takePhoto
        blinkDetected = false
        capturedPhoto = nil
        camera.resetCapture()
    }

    // MARK: - Intro screen

    private var introScreen: some View {
        ZStack {
            AppTheme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // Hero icon
                ZStack {
                    Circle()
                        .fill(AppTheme.pink.opacity(0.1))
                        .frame(width: 100, height: 100)
                    Circle()
                        .fill(AppTheme.pink.opacity(0.06))
                        .frame(width: 140, height: 140)
                    Image(systemName: "faceid")
                        .font(.system(size: 48, weight: .light))
                        .foregroundStyle(AppTheme.primaryGradient)
                }
                .padding(.bottom, 28)

                Text("Verify Your Identity")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundColor(AppTheme.textPrimary)
                    .padding(.bottom, 8)

                Text("A quick selfie confirms you're the person\nin your profile photos.")
                    .font(.system(size: 15, design: .rounded))
                    .foregroundColor(AppTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 40)

                // Checklist
                VStack(spacing: 0) {
                    introCheckRow(
                        icon: "sun.max.fill",
                        color: Color.yellow,
                        title: "Good lighting",
                        subtitle: "Face a window or bright light source"
                    )
                    Divider().background(AppTheme.surface).padding(.leading, 58)
                    introCheckRow(
                        icon: "face.smiling.inverse",
                        color: AppTheme.pink,
                        title: "Face the camera directly",
                        subtitle: "Remove glasses or hats if you can"
                    )
                    Divider().background(AppTheme.surface).padding(.leading, 58)
                    introCheckRow(
                        icon: "eye.fill",
                        color: AppTheme.purple,
                        title: "Be ready to blink",
                        subtitle: "You'll be asked to blink once to prove you're live"
                    )
                }
                .background(AppTheme.surface.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .padding(.horizontal, 24)
                .padding(.bottom, 36)

                Spacer()

                // CTA / denied state
                VStack(spacing: 12) {
                    if permissionDenied {
                        VStack(spacing: 10) {
                            HStack(spacing: 8) {
                                Image(systemName: "camera.slash.fill")
                                    .font(.system(size: 14))
                                    .foregroundColor(AppTheme.pink)
                                Text("Camera access was denied")
                                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                                    .foregroundColor(AppTheme.textPrimary)
                            }
                            Text("Enable camera access in Settings to continue.")
                                .font(.system(size: 13, design: .rounded))
                                .foregroundColor(AppTheme.textSecondary)
                                .multilineTextAlignment(.center)

                            Button {
                                if let url = URL(string: UIApplication.openSettingsURLString) {
                                    UIApplication.shared.open(url)
                                }
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "gear")
                                        .font(.system(size: 15, weight: .semibold))
                                    Text("Open Settings")
                                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                                }
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(AppTheme.primaryGradient)
                                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    } else {
                        Button {
                            Task { await requestPermissionAndProceed() }
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "camera.fill")
                                    .font(.system(size: 16, weight: .semibold))
                                Text("Get Started")
                                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(AppTheme.primaryGradient)
                            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 48)
            }
        }
    }

    private func introCheckRow(icon: String, color: Color, title: String, subtitle: String) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(color.opacity(0.15))
                    .frame(width: 38, height: 38)
                Image(systemName: icon)
                    .font(.system(size: 17))
                    .foregroundColor(color)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(AppTheme.textPrimary)
                Text(subtitle)
                    .font(.system(size: 12, design: .rounded))
                    .foregroundColor(AppTheme.textSecondary)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    @MainActor
    private func requestPermissionAndProceed() async {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            camera.setup()
            verificationStep = .takePhoto
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            if granted {
                camera.setup()
                verificationStep = .takePhoto
            } else {
                permissionDenied = true
            }
        default:
            permissionDenied = true
        }
    }

    // MARK: - Camera screen

    private var cameraScreen: some View {
        ZStack(alignment: .bottom) {
            Color.black.ignoresSafeArea()

            if camera.isAuthorized && (verificationStep == .takePhoto || verificationStep == .livenessCheck) {
                CameraPreviewView(session: camera.captureSession)
                    .ignoresSafeArea()
            }

            // Face oval — centered in camera area above the bottom panel
            if !blinkDetected, camera.isAuthorized,
               verificationStep == .takePhoto || verificationStep == .livenessCheck {
                GeometryReader { geo in
                    faceOvalGuide
                        .frame(width: 160, height: 210)
                        .position(
                            x: geo.size.width / 2,
                            y: (geo.size.height - bottomPanelHeight) / 2
                        )
                }
                .ignoresSafeArea()
            }

            // Blink success flash
            if blinkDetected {
                blinkSuccessOverlay
            }

            // LIVE badge
            if verificationStep == .livenessCheck, !blinkDetected {
                livenessIndicator
            }

            // Bottom instruction + action panel
            bottomPanel
        }
    }

    // MARK: - Bottom panel

    private var bottomPanel: some View {
        VStack(spacing: 0) {
            // Frosted top edge gradient
            LinearGradient(
                colors: [Color.black.opacity(0), Color.black.opacity(0.85)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 60)

            VStack(spacing: 16) {
                instructionsCard

                if case .failed(let ids) = verificationStep {
                    mismatchErrorCard(mismatchedPhotoIds: ids)
                }

                actionBar
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 36)
            .background(Color.black.opacity(0.85))
        }
    }

    // MARK: - Instructions card

    private var instructionsCard: some View {
        VStack(spacing: 0) {
            // Step tracker row
            HStack(alignment: .center, spacing: 0) {
                stepDot(number: "1", label: "Take Photo", active: verificationStep == .takePhoto, done: isDoneWithStep1)

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.12))
                        .frame(height: 3)
                    Capsule()
                        .fill(AppTheme.primaryGradient)
                        .frame(height: 3)
                        .opacity(isDoneWithStep1 ? 1 : 0)
                        .animation(.easeInOut(duration: 0.4), value: isDoneWithStep1)
                }

                stepDot(number: "2", label: "Blink", active: verificationStep == .livenessCheck, done: blinkDetected)
            }
            .padding(.bottom, 14)

            // Instruction row
            HStack(spacing: 10) {
                Image(systemName: currentStepIcon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppTheme.primaryGradient)
                    .frame(width: 30, height: 30)
                    .background(Color.white.opacity(0.1))
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(currentStepTitle)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Text(currentStepSubtitle)
                        .font(.system(size: 12, design: .rounded))
                        .foregroundColor(.white.opacity(0.6))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                // Live tips — 3 tiny chips
                HStack(spacing: 6) {
                    ForEach(currentTips, id: \.0) { tip in
                        tipChip(icon: tip.0, text: tip.1)
                    }
                }
            }
        }
        .animation(.easeInOut(duration: 0.3), value: verificationStep)
    }

    private var isDoneWithStep1: Bool {
        switch verificationStep {
        case .takePhoto: return false
        default: return true
        }
    }

    private var currentStepIcon: String {
        verificationStep == .takePhoto ? "camera.fill" : "eye.fill"
    }

    private var currentStepTitle: String {
        verificationStep == .takePhoto ? "Take a Selfie" : "Liveness Check"
    }

    private var currentStepSubtitle: String {
        verificationStep == .takePhoto
            ? "Position your face in the oval below."
            : "Blink once to confirm you're real."
    }

    private var currentTips: [(String, String)] {
        verificationStep == .takePhoto
            ? [("sun.max", "Light"), ("face.smiling", "Forward"), ("camera", "Steady")]
            : [("eye", "Look"), ("bolt.fill", "Blink"), ("checkmark.circle", "Still")]
    }

    private func stepDot(number: String, label: String, active: Bool, done: Bool) -> some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(done ? AppTheme.green : (active ? AppTheme.pink : Color.white.opacity(0.15)))
                    .frame(width: 24, height: 24)
                if done {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                } else {
                    Text(number)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(active ? .white : Color.white.opacity(0.4))
                }
            }
            Text(label)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundColor(done ? AppTheme.green : (active ? .white : Color.white.opacity(0.4)))
        }
    }

    private func tipChip(icon: String, text: String) -> some View {
        VStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.7))
            Text(text)
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.5))
        }
        .frame(width: 36)
        .padding(.vertical, 5)
        .background(Color.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    // MARK: - Action bar

    private var actionBar: some View {
        Group {
            switch verificationStep {
            case .takePhoto:
                Button {
                    camera.capturePhoto()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 16, weight: .semibold))
                        Text("Capture Photo")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(AppTheme.primaryGradient)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                }
                .buttonStyle(.plain)

            case .livenessCheck:
                VStack(spacing: 10) {
                    if blinkTimedOut {
                        Text("Try better lighting or hold your face steady.")
                            .font(.system(size: 12, design: .rounded))
                            .foregroundColor(.white.opacity(0.6))
                            .multilineTextAlignment(.center)
                        Button {
                            blinkTimedOut = false
                            camera.resetBlinkDetection()
                            blinkTimeoutTask?.cancel()
                            blinkTimeoutTask = Task { @MainActor in
                                try? await Task.sleep(nanoseconds: 15_000_000_000)
                                guard !Task.isCancelled, verificationStep == .livenessCheck, !blinkDetected else { return }
                                blinkTimedOut = true
                            }
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 16, weight: .semibold))
                                Text("Retry Blink Detection")
                                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(AppTheme.primaryGradient)
                            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    } else {
                        HStack(spacing: 10) {
                            ProgressView().tint(.white)
                            Text("Waiting for blink…")
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                .foregroundColor(.white)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.white.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    }
                }

            case .uploading, .pendingVerification:
                HStack(spacing: 12) {
                    Circle()
                        .fill(.white)
                        .frame(width: 7, height: 7)
                        .scaleEffect(uploadPulse ? 1.0 : 0.5)
                        .opacity(uploadPulse ? 1.0 : 0.4)
                        .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true).delay(0.0), value: uploadPulse)
                    Circle()
                        .fill(.white)
                        .frame(width: 7, height: 7)
                        .scaleEffect(uploadPulse ? 1.0 : 0.5)
                        .opacity(uploadPulse ? 1.0 : 0.4)
                        .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true).delay(0.15), value: uploadPulse)
                    Circle()
                        .fill(.white)
                        .frame(width: 7, height: 7)
                        .scaleEffect(uploadPulse ? 1.0 : 0.5)
                        .opacity(uploadPulse ? 1.0 : 0.4)
                        .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true).delay(0.3), value: uploadPulse)
                    Text("Uploading selfie…")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(AppTheme.primaryGradient.opacity(uploadPulse ? 1.0 : 0.75))
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: uploadPulse)
                .onAppear { uploadPulse = true }
                .onDisappear { uploadPulse = false }

            case .done, .intro:
                EmptyView()

            case .failed:
                Button {
                    onComplete?()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "photo.stack")
                            .font(.system(size: 16, weight: .semibold))
                        Text("Update Photos")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(AppTheme.primaryGradient)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Overlays

    private var faceOvalGuide: some View {
        Ellipse()
            .stroke(
                verificationStep == .livenessCheck
                    ? LinearGradient(colors: [AppTheme.pink, AppTheme.purple], startPoint: .top, endPoint: .bottom)
                    : LinearGradient(colors: [Color.white.opacity(0.5), Color.white.opacity(0.25)], startPoint: .top, endPoint: .bottom),
                lineWidth: 2.5
            )
            .frame(width: 170, height: 220)
    }

    private var livenessIndicator: some View {
        VStack {
            HStack {
                Spacer()
                HStack(spacing: 6) {
                    Circle()
                        .fill(AppTheme.pink)
                        .frame(width: 8, height: 8)
                        .scaleEffect(blinkPulse ? 1.4 : 1.0)
                        .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: blinkPulse)
                    Text("LIVE")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.black.opacity(0.55))
                .clipShape(Capsule())
                .padding(.top, 60)
                .padding(.trailing, 20)
            }
            Spacer()
        }
        .ignoresSafeArea()
        .onAppear { blinkPulse = true }
    }

    private var blinkSuccessOverlay: some View {
        Color.black.opacity(0.5)
            .ignoresSafeArea()
            .overlay(
                VStack(spacing: 14) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 64))
                        .foregroundColor(AppTheme.green)
                    Text("Blink Detected!")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }
            )
            .transition(.opacity.combined(with: .scale(scale: 0.92)))
            .animation(.spring(response: 0.35), value: blinkDetected)
    }

    // MARK: - Mismatch error card

    private func mismatchErrorCard(mismatchedPhotoIds: [String]) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(AppTheme.pink.opacity(0.2))
                    .frame(width: 40, height: 40)
                Image(systemName: "person.2.slash")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(AppTheme.primaryGradient)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("Photos don't match")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Text(mismatchedPhotoIds.isEmpty
                    ? "Ensure your profile photos clearly show your face."
                    : "\(mismatchedPhotoIds.count) photo\(mismatchedPhotoIds.count == 1 ? "" : "s") appear to show a different person.")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundColor(.white.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding(14)
        .background(AppTheme.pink.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(AppTheme.pink.opacity(0.35), lineWidth: 1)
        )
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

}

// MARK: - SwipeBackEnabler — re-enables the interactive pop gesture when navigationBarBackButtonHidden

private struct SwipeBackEnabler: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIViewController { UIViewController() }
    func updateUIViewController(_ vc: UIViewController, context: Context) {
        DispatchQueue.main.async {
            vc.navigationController?.interactivePopGestureRecognizer?.isEnabled = true
            vc.navigationController?.interactivePopGestureRecognizer?.delegate = nil
        }
    }
}

// MARK: - UIImage resize helper

private extension UIImage {
    /// Downscales to a max of 1440px on the long edge, preserving aspect ratio.
    /// At 0.95 JPEG quality this produces ~400–700 KB — sharp enough for ArcFace,
    /// well under the 5 MB backend limit.
    func resizedForVerification(maxLongEdge: CGFloat = 1440) -> UIImage? {
        let long = max(size.width, size.height)
        guard long > maxLongEdge else { return self }
        let scale = maxLongEdge / long
        let newSize = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in draw(in: CGRect(origin: .zero, size: newSize)) }
    }
}

// MARK: - Camera preview UIViewRepresentable

struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewUIView, context: Context) {}

    class PreviewUIView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}

// MARK: - Blink state (accessed from background capture thread)

private final class BlinkState: @unchecked Sendable {
    private let lock = NSLock()
    private var _active = false

    private enum Phase { case warmup, ready, sawClose }
    private var _phase: Phase = .warmup
    private var _openCount = 0
    private var _noiseCount = 0  // tolerated noise frames during warmup
    private var _closedCount = 0

    private let warmupRequired = 8
    private let warmupNoiseTolerance = 2  // allow up to 2 noisy frames without full reset
    private let minClosedStreak = 2       // reduced from 3 — EAR is stable enough

    var isActive: Bool {
        lock.withLock { _active }
    }

    func activate() {
        lock.withLock {
            _active = true
            _phase = .warmup
            _openCount = 0
            _noiseCount = 0
            _closedCount = 0
        }
    }

    func deactivate() {
        lock.withLock {
            _active = false
            _phase = .warmup
            _openCount = 0
            _noiseCount = 0
            _closedCount = 0
        }
    }

    /// Pass nil for indeterminate frames (no landmarks detected) — they are skipped.
    /// Returns true the moment a genuine blink completes (eyes reopen after closed streak).
    func record(eyesOpen: Bool?) -> Bool {
        lock.withLock {
            guard let eyesOpen else { return false }

            switch _phase {
            case .warmup:
                if eyesOpen {
                    _openCount += 1
                    if _openCount >= warmupRequired { _phase = .ready }
                } else {
                    _noiseCount += 1
                    if _noiseCount > warmupNoiseTolerance {
                        _openCount = 0
                        _noiseCount = 0
                    }
                }
                return false

            case .ready:
                if !eyesOpen {
                    _phase = .sawClose
                    _closedCount = 1
                }
                return false

            case .sawClose:
                if !eyesOpen {
                    _closedCount += 1
                    return false
                } else {
                    let count = _closedCount
                    _closedCount = 0
                    if count >= minClosedStreak {
                        _active = false
                        return true
                    }
                    _phase = .ready
                    return false
                }
            }
        }
    }
}

// MARK: - Camera manager

// Normalised rects (0–1) in SwiftUI coordinate space (top-left origin, y down)
// for the left and right eye, published to the UI for the overlay.
struct EyeRects: Equatable {
    var left: CGRect   // from camera's perspective (user's right eye)
    var right: CGRect  // from camera's perspective (user's left eye)
}

@MainActor
final class CameraManager: NSObject, ObservableObject {
    @Published var isAuthorized = false
    @Published var capturedImage: UIImage? = nil
    @Published var blinkDetected = false
    @Published var eyeRects: EyeRects? = nil

    let captureSession = AVCaptureSession()
    private var photoOutput = AVCapturePhotoOutput()
    private var videoOutput = AVCaptureVideoDataOutput()
    private let blinkState = BlinkState()

    func setup() {
        Task {
            let status = AVCaptureDevice.authorizationStatus(for: .video)
            if status == .notDetermined {
                await AVCaptureDevice.requestAccess(for: .video)
            }
            await configureSession()
        }
    }

    func teardown() {
        blinkState.deactivate()
        if captureSession.isRunning {
            Task.detached { [captureSession] in captureSession.stopRunning() }
        }
    }

    func capturePhoto() {
        let settings = AVCapturePhotoSettings()
        settings.flashMode = .off
        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    func startBlinkDetection() {
        blinkState.activate()
    }

    func resetCapture() {
        capturedImage = nil
        blinkDetected = false
        blinkState.deactivate()
    }

    func resetBlinkDetection() {
        blinkDetected = false
        blinkState.deactivate()
        blinkState.activate()
    }

    private func configureSession() async {
        let authorized = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
        isAuthorized = authorized
        guard authorized else { return }

        captureSession.beginConfiguration()
        captureSession.sessionPreset = .photo

        if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
           let input = try? AVCaptureDeviceInput(device: device),
           captureSession.canAddInput(input) {
            captureSession.addInput(input)
        }

        if captureSession.canAddOutput(photoOutput) {
            captureSession.addOutput(photoOutput)
        }

        videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "blink.detection"))
        videoOutput.alwaysDiscardsLateVideoFrames = true
        if captureSession.canAddOutput(videoOutput) {
            captureSession.addOutput(videoOutput)
        }

        captureSession.commitConfiguration()
        Task.detached { [captureSession] in captureSession.startRunning() }
    }
}

// MARK: - AVCapturePhotoCaptureDelegate

extension CameraManager: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        guard error == nil,
              let data = photo.fileDataRepresentation(),
              let image = UIImage(data: data) else { return }

        // Mirror the image since front camera preview is mirrored
        let mirrored = UIImage(cgImage: image.cgImage!, scale: image.scale, orientation: .leftMirrored)
        Task { @MainActor in
            self.capturedImage = mirrored
        }
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate (blink detection)

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard blinkState.isActive else { return }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let request = VNDetectFaceLandmarksRequest { [weak self] req, _ in
            guard let self else { return }
            guard let results = req.results as? [VNFaceObservation],
                  let face = results.first else {
                Task { @MainActor in self.eyeRects = nil }
                return
            }

            let leftEAR = eyeAspectRatio(face.landmarks?.leftEye)
            let rightEAR = eyeAspectRatio(face.landmarks?.rightEye)

            let rects = EyeRects(
                left: eyeRect(face.landmarks?.leftEye, faceBB: face.boundingBox),
                right: eyeRect(face.landmarks?.rightEye, faceBB: face.boundingBox)
            )
            Task { @MainActor in self.eyeRects = rects }

            // nil = indeterminate (landmarks missing); skip frame in state machine
            let eyesOpen: Bool? = {
                guard let left = leftEAR, let right = rightEAR else { return nil }
                let avgEAR = (left + right) / 2.0
                return avgEAR > 0.2
            }()

            let blinkFired = self.blinkState.record(eyesOpen: eyesOpen)

            guard blinkFired else { return }
            Task { @MainActor in
                guard !self.blinkDetected else { return }
                self.blinkDetected = true
            }
        }

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .leftMirrored, options: [:])
        try? handler.perform([request])
    }

    private nonisolated func eyeRect(_ region: VNFaceLandmarkRegion2D?, faceBB: CGRect) -> CGRect {
        guard let pts = region?.normalizedPoints, pts.count >= 2 else { return .zero }
        let xs = pts.map { faceBB.minX + $0.x * faceBB.width }
        let ys = pts.map { faceBB.minY + $0.y * faceBB.height }
        let minX = xs.min() ?? 0; let maxX = xs.max() ?? 0
        let minY = ys.min() ?? 0; let maxY = ys.max() ?? 0
        let pad: CGFloat = 0.02
        let rect = CGRect(x: minX - pad, y: minY - pad, width: (maxX - minX) + pad * 2, height: (maxY - minY) + pad * 2)
        return CGRect(x: rect.minX, y: 1 - rect.maxY, width: rect.width, height: rect.height)
    }

    /// Eye Aspect Ratio — scale-invariant measure of how open an eye is.
    /// Returns nil if landmarks are insufficient (indeterminate).
    /// Uses vertical/horizontal ratio of the eye landmark points.
    private nonisolated func eyeAspectRatio(_ region: VNFaceLandmarkRegion2D?) -> CGFloat? {
        guard let pts = region?.normalizedPoints, pts.count >= 6 else { return nil }
        // Vision eye landmarks are ordered roughly: outer corner, top points, inner corner, bottom points
        // Use bounding box approach: vertical span / horizontal span
        let xs = pts.map { $0.x }
        let ys = pts.map { $0.y }
        let width = (xs.max() ?? 0) - (xs.min() ?? 0)
        guard width > 0.001 else { return nil }
        let height = (ys.max() ?? 0) - (ys.min() ?? 0)
        return height / width
    }
}
