import SwiftUI

@main
struct ClubMatesApp: App {
    @StateObject private var session = AppSessionStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(session)
                .preferredColorScheme(.dark)
        }
    }
}
