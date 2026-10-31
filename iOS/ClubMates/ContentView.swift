import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var session: AppSessionStore

    @State private var onboardingDraft = UserProfile(
        name: "", age: 21, bio: "", distance: 0,
        prompts: [], photos: [], interests: [],
        profession: "Student", gender: "Male",
        height: 170, isVerified: false, lookingFor: "",
        preferences: .default
    )

    private var onboardingDraftBinding: Binding<UserProfile> {
        Binding(get: { onboardingDraft }, set: { onboardingDraft = $0 })
    }

    var body: some View {
        Group {
            if session.isAuthenticated {
                MainTabView()
            } else if session.needsProfileCreation {
                onboardingStep
            } else {
                WelcomeView()
            }
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.85), value: session.isAuthenticated)
        .animation(.spring(response: 0.28, dampingFraction: 0.85), value: session.needsProfileCreation)
        .animation(.spring(response: 0.28, dampingFraction: 0.85), value: session.onboardingStep)
    }

    @ViewBuilder
    private var onboardingStep: some View {
        switch session.onboardingStep {
        case .basics:
            OnboardingBasicsView(draft: onboardingDraftBinding, onNext: { session.advanceOnboardingStep() })
        case .vibe:
            OnboardingVibeView(draft: onboardingDraftBinding, onBack: { session.rewindOnboardingStep() }, onNext: { session.advanceOnboardingStep() })
        case .preferences:
            OnboardingPreferencesView(draft: onboardingDraftBinding, onBack: { session.rewindOnboardingStep() }, onFinish: { session.completeProfile(onboardingDraft) })
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(AppSessionStore())
    }
}
