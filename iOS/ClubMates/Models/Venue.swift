import SwiftUI

struct Venue: Identifiable, Hashable {
    let id: UUID
    let name: String
    let city: String
    let neighborhood: String
    let vibe: String
    let music: String
    let symbolName: String
    let gradientHex: [String]
    let latitude: Double?
    let longitude: Double?
    let checkinRadiusMeters: Int

    init(
        id: UUID = UUID(),
        name: String,
        city: String = "Hyderabad",
        neighborhood: String,
        vibe: String,
        music: String,
        symbolName: String,
        gradientHex: [String],
        latitude: Double? = nil,
        longitude: Double? = nil,
        checkinRadiusMeters: Int = 200
    ) {
        self.id = id
        self.name = name
        self.city = city
        self.neighborhood = neighborhood
        self.vibe = vibe
        self.music = music
        self.symbolName = symbolName
        self.gradientHex = gradientHex
        self.latitude = latitude
        self.longitude = longitude
        self.checkinRadiusMeters = checkinRadiusMeters
    }

    var gradient: LinearGradient {
        let colors = gradientHex.map { Color(hex: $0) }
        return LinearGradient(
            colors: colors.isEmpty ? [AppTheme.surface, AppTheme.surfaceElevated] : colors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}
