# Testing Setup
<!-- Repository documentation; excluded from runtime deployment. -->

This project now includes a testing foundation for both backend and iOS.

## Backend (Vitest)

### Install dependencies

```bash
cd Backend
npm install
```

### Run tests

```bash
npm run test
npm run test:watch
npm run test:unit
npm run test:integration
npm run test:coverage
```

### Current backend test structure

- `tests/setup/env.ts` — test env defaults + common hooks.
- `tests/unit/http-utils.test.ts` — pure helper unit tests.
- `tests/integration/health.test.ts` — app-level integration via Fastify inject.

### Recommended next backend tests

1. Auth OTP send/verify/refresh route flow (mock OTP provider).
2. Venue check-in radius allow/deny.
3. Block/report visibility filtering in roster/discover/matches.
4. Messaging send/read + websocket event propagation.
5. Account deletion lifecycle + purge job.

---

## iOS (XCTest + XCUITest)

Added test source files:

- `iOS/ClubMatesTests/ClubMatesTests.swift`
- `iOS/ClubMatesUITests/ClubMatesUITests.swift`

### One-time Xcode target setup

1. Open `iOS/ClubMates.xcodeproj`.
2. Add Unit Test target named `ClubMatesTests` (if not present).
3. Add UI Test target named `ClubMatesUITests` (if not present).
4. Ensure both targets include the files above.
5. For unit tests, set **Host Application** to `ClubMates`.

### Run iOS tests

- In Xcode: `Product > Test` (`Cmd+U`)
- Or CLI:

```bash
xcodebuild \
  -project iOS/ClubMates.xcodeproj \
  -scheme ClubMates \
  -destination 'platform=iOS Simulator,name=iPhone 16e' \
  test
```

### Recommended next iOS tests

1. Session store auth state transitions.
2. Discover view model check-in/checkout behavior (mock network).
3. SafetyVisibilityStore persistence and filtering.
4. Matches view model message list update behavior.
5. UI smoke flow: launch → login screen visible.
