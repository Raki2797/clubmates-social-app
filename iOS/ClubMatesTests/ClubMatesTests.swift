import XCTest
@testable import ClubMates

final class ClubMatesTests: XCTestCase {
    func testUserProfileMainPhotoUsesFirstPhoto() {
        let first = ProfilePhoto(systemName: "person.fill")
        let second = ProfilePhoto(systemName: "photo.fill")
        let profile = UserProfile(
            name: "Tester",
            age: 25,
            bio: "Bio",
            distance: 0,
            photos: [first, second]
        )

        XCTAssertEqual(profile.mainPhoto?.id, first.id)
    }

    func testSafetyVisibilityFiltersHiddenUsers() {
        let visible = UserProfile(id: UUID(), name: "Visible", age: 24, bio: "", distance: 0)
        let hidden = UserProfile(id: UUID(), name: "Hidden", age: 24, bio: "", distance: 0)

        SafetyVisibilityStore.hide(hidden.id)
        let filtered = SafetyVisibilityStore.visibleProfiles([visible, hidden])

        XCTAssertEqual(filtered.map(\.id), [visible.id])
    }
}

