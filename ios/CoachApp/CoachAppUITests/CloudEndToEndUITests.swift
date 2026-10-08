import XCTest

/// Every iOS workflow against the REAL Firestore database (and real
/// Gemini), signed in as a throwaway allow-listed account. Skipped unless
/// a Firebase custom token is supplied:
///   TEST_RUNNER_COACH_E2E_TOKEN=<token> xcodebuild test … -only-testing:CoachAppUITests/CloudEndToEndUITests
/// An admin script seeds the account beforehand and checks every write
/// in Firestore afterwards (see ios/README.md → End-to-end check).
final class CloudEndToEndUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        guard let token = ProcessInfo.processInfo.environment["COACH_E2E_TOKEN"], !token.isEmpty else {
            throw XCTSkip("no COACH_E2E_TOKEN — the cloud end-to-end run needs a throwaway account")
        }
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["COACH_DEBUG_CUSTOM_TOKEN"] = token
        app.launch()
    }

    private func button(_ label: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label ==[c] %@", label)).firstMatch
    }
    private func text(_ label: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label ==[c] %@", label)).firstMatch
    }
    private func textBeginning(_ prefix: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH[c] %@", prefix)).firstMatch
    }
    private func scrollTo(_ el: XCUIElement, max: Int = 10) {
        for _ in 0..<max where !el.isHittable { app.swipeUp() }
    }
    private func type(_ field: XCUIElement, _ s: String) {
        field.tap()
        field.typeText(s)
    }
    /// Focus, Select All from the edit menu, type over it.
    private func replace(_ field: XCUIElement, with s: String) {
        field.tap()
        field.press(forDuration: 1.2)
        let selectAll = app.menuItems["Select All"]
        if selectAll.waitForExistence(timeout: 3) { selectAll.tap() } else { field.doubleTap() }
        field.typeText(s)
    }

    func testEveryWorkflowAgainstTheRealDatabase() {
        XCTContext.runActivity(named: "signed in: Home with the account's data") { _ in
            XCTAssertTrue(text("Ready, Verify?").waitForExistence(timeout: 30))
        }

        XCTContext.runActivity(named: "quick cardio: 25 min run") { _ in
            button("Run").tap()
            XCTAssertTrue(text("Log a run").waitForExistence(timeout: 5))
            type(app.textFields["min"], "25")
            text("Log a run").tap()
            button("🏃 Save run").tap()
            XCTAssertTrue(text("Log a run").waitForNonExistence(timeout: 10), "run saved")
        }

        XCTContext.runActivity(named: "check-in → real AI plan → workout") { _ in
            button("Start workout").tap()
            XCTAssertTrue(text("Check-in").waitForExistence(timeout: 10))
            let build = button("Build session")
            scrollTo(build)
            build.tap()
            XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label MATCHES '0/[0-9]+ sets'")).firstMatch.waitForExistence(timeout: 120),
                          "the AI plan arrived and the workout screen opened")
        }

        XCTContext.runActivity(named: "log a set → rest timer → finish → save") { _ in
            app.buttons["Set 1"].firstMatch.tap()
            XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label MATCHES '1/[0-9]+ sets'")).firstMatch.waitForExistence(timeout: 5))
            XCTAssertTrue(app.descendants(matching: .any)["rest-bar"].waitForExistence(timeout: 5))
            button("Skip").tap()
            let finish = button("Finish session")
            scrollTo(finish, max: 25)
            finish.tap()
            XCTAssertTrue(text("How did it go?").waitForExistence(timeout: 5))
            type(app.textFields["e.g. curls felt brutal"], "e2e verify")
            button("Save session").tap()
            XCTAssertTrue(button("Plan another session").waitForExistence(timeout: 15))
        }

        XCTContext.runActivity(named: "log: edit today's workout RPE to 9") { _ in
            button("Log").tap()
            XCTAssertTrue(text("Log").waitForExistence(timeout: 5))
            app.buttons.matching(NSPredicate(format: "label == %@", "Session options")).element(boundBy: 0).tap()
            button("Edit").tap()
            let rpe = app.textFields.matching(NSPredicate(format: "placeholderValue == '1-10'")).firstMatch
            XCTAssertTrue(rpe.waitForExistence(timeout: 5))
            replace(rpe, with: "9")
            let save = button("Save changes")
            scrollTo(save)
            save.tap()
            XCTAssertTrue(textBeginning("RPE 9").waitForExistence(timeout: 10))
        }

        XCTContext.runActivity(named: "past workout: add, then delete it") { _ in
            button("Add past workout").tap()
            XCTAssertTrue(text("Past workout").waitForExistence(timeout: 5))
            type(app.textFields["Exercise"], "Verify Curl")
            type(app.textFields.matching(NSPredicate(format: "placeholderValue == 'kg'")).firstMatch, "20")
            type(app.textFields.matching(NSPredicate(format: "placeholderValue == 'reps'")).firstMatch, "10")
            text("Past workout").tap()
            let save = button("Save")
            scrollTo(save)
            save.tap()
            let card = text("Verify Curl: 20kg×10")
            XCTAssertTrue(card.waitForExistence(timeout: 10))
            // newest first: today's workout, today's run, then yesterday's past workout
            app.buttons.matching(NSPredicate(format: "label == %@", "Session options")).element(boundBy: 2).tap()
            button("Delete").tap()
            button("Delete").tap()
            XCTAssertTrue(card.waitForNonExistence(timeout: 10))
            button("Today").tap()
        }

        XCTContext.runActivity(named: "coach chat: a real answer") { _ in
            app.buttons["Ask the coach"].tap()
            XCTAssertTrue(app.buttons["Close chat"].waitForExistence(timeout: 5))
            type(app.textFields["Ask the coach…"], "Reply with the single word banana and nothing else.")
            app.buttons["Send"].tap()
            XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label MATCHES[c] '\\\\W*banana\\\\W*'")).firstMatch.waitForExistence(timeout: 60),
                          "the coach answered")
            app.buttons["Close chat"].tap()
        }

        XCTContext.runActivity(named: "records + progress render") { _ in
            button("Records").tap()
            XCTAssertTrue(text("Personal records").waitForExistence(timeout: 5))
            button("Progress").tap()
            XCTAssertTrue(text("Training days").waitForExistence(timeout: 5))
            button("Today").tap()
        }

        XCTContext.runActivity(named: "settings: gym setup + feedback") { _ in
            app.buttons["Settings"].tap()
            XCTAssertTrue(text("About COACH").waitForExistence(timeout: 5))
            app.staticTexts["Barbell & plate setup"].tap()
            let plates = app.textFields.matching(NSPredicate(format: "value CONTAINS '2.5'")).firstMatch
            XCTAssertTrue(plates.waitForExistence(timeout: 5))
            replace(plates, with: "20, 10, 5")
            button("Save gym setup").tap()
            XCTAssertTrue(button("✓ Saved").waitForExistence(timeout: 5))
            button("Close").tap()

            app.staticTexts["Send feedback"].tap()
            let fbQuery = NSPredicate(format: "placeholderValue BEGINSWITH 'Bugs, ideas'")
            let fb = app.textViews.matching(fbQuery).firstMatch.exists ? app.textViews.matching(fbQuery).firstMatch : app.textFields.matching(fbQuery).firstMatch
            type(fb, "e2e verify feedback")
            button("Send feedback").tap()
            XCTAssertTrue(text("✓ Sent — thank you!").waitForExistence(timeout: 15))
            button("Close").tap()
        }

        XCTContext.runActivity(named: "sign out → login screen") { _ in
            let out = button("Sign out")
            scrollTo(out)
            out.tap()
            button("Tap again — this wipes this device").tap()
            XCTAssertTrue(button("Sign in with Google").waitForExistence(timeout: 15))
        }
    }
}
