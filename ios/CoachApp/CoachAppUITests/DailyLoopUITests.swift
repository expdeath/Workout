import XCTest

/// Drives the real UI in the simulator. Every launch uses DebugSeed
/// (COACH_DEBUG_SEED=1): a wiped store, a fake account + Gemini key, one
/// old Push session, and today's Watch health row.
final class DailyLoopUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["COACH_DEBUG_SEED"] = "1"
        app.launch()
    }

    private func button(_ label: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label ==[c] %@", label)).firstMatch
    }

    private func text(_ label: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label ==[c] %@", label)).firstMatch
    }

    private var readiness: String? {
        app.descendants(matching: .any)["readiness"].value as? String
    }

    func testCheckInUpdatesReadinessAndSurfacesAIError() {
        XCTAssertTrue(button("Start check-in").waitForExistence(timeout: 10))
        button("Start check-in").tap()
        XCTAssertTrue(text("CHECK-IN").waitForExistence(timeout: 5))

        // normal day: 50 + energy 7 (+10) + OK sleep (+5) + no soreness (+10)
        XCTAssertEqual(readiness, "75")
        // seeded Watch row → details open with the loaded note
        XCTAssertTrue(text("⌚ Watch data loaded — the coach will read it").exists)

        button("Poor").tap()
        XCTAssertEqual(readiness, "55")

        button("Very sore").tap()
        XCTAssertEqual(readiness, "25")
        XCTAssertTrue(app.textFields["Where? e.g. chest, quads"].exists)

        button("Lower back tight today?").tap()
        XCTAssertTrue(button("✓ Lower back tight today — coach will adapt").exists)
        XCTAssertEqual(readiness, "17")

        // hiding details keeps answers
        button("− Hide more details").tap()
        XCTAssertFalse(button("✓ Lower back tight today — coach will adapt").exists)
        button("+ More details — back, vibe, health data").tap()
        XCTAssertTrue(button("✓ Lower back tight today — coach will adapt").exists)

        // the seeded key is fake → Gemini rejects it → back on check-in
        // with the error shown and the answers intact
        let build = button("Build today's session")
        app.swipeUp()
        app.swipeUp()
        build.tap()
        XCTAssertTrue(app.staticTexts["error"].waitForExistence(timeout: 90))
        XCTAssertTrue(text("CHECK-IN").exists)
        XCTAssertEqual(readiness, "17")
        XCTAssertTrue(button("Poor").isSelected)

        app.swipeDown()
        app.swipeDown()
        button("Cancel").tap()
        XCTAssertTrue(button("Start check-in").waitForExistence(timeout: 5))
    }

    func testBackdatedQuickCardioDoesNotBecomeLastSession() {
        XCTAssertTrue(button("🏃 Run").waitForExistence(timeout: 10))

        // today's run
        logCardio(open: "🏃 Run", title: "Log a run", save: "🏃 Save run", minutes: "30", day: nil)
        XCTAssertTrue(text("Run").waitForExistence(timeout: 5))

        // yesterday's ride — logged later, but must sort before today's run
        logCardio(open: "🚴 Ride", title: "Log a ride", save: "🚴 Save ride", minutes: "45", day: "Yesterday")
        XCTAssertTrue(text("Run").waitForExistence(timeout: 5))
        XCTAssertFalse(text("Cycle").exists, "backdated ride replaced today's run as Last session")
        XCTAssertTrue(text("Session RPE 6/10").exists)
    }

    private func logCardio(open: String, title: String, save: String, minutes: String, day: String?) {
        button(open).tap()
        XCTAssertTrue(text(title).waitForExistence(timeout: 5))
        XCTAssertFalse(button(save).isEnabled, "save should wait for a time or distance")
        if let day { button(day).tap() }
        let min = app.textFields["min"]
        min.tap()
        min.typeText(minutes)
        text(title).tap() // dismiss the keyboard
        XCTAssertTrue(button(save).isEnabled)
        button(save).tap()
        XCTAssertTrue(text(title).waitForNonExistence(timeout: 5))
    }
}
