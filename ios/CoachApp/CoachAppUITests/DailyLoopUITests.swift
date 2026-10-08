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
        XCTAssertTrue(button("Start workout").waitForExistence(timeout: 10))
        button("Start workout").tap()
        XCTAssertTrue(text("Check-in").waitForExistence(timeout: 5))

        // normal day: 50 + energy 7 (+10) + OK sleep (+5) + no soreness (+10)
        XCTAssertEqual(readiness, "75")
        // seeded Watch row → details open with the loaded note
        XCTAssertTrue(text("Loaded from Watch").exists)

        button("Poor").tap()
        XCTAssertEqual(readiness, "55")

        button("Very sore").tap()
        XCTAssertEqual(readiness, "25")
        XCTAssertTrue(app.textFields["Where?"].exists)

        button("Lower back tight?").tap()
        XCTAssertTrue(button("✓ Lower back tight").exists)
        XCTAssertEqual(readiness, "17")

        // hiding details keeps answers
        button("Fewer details").tap()
        XCTAssertFalse(button("✓ Lower back tight").exists)
        button("More details").tap()
        XCTAssertTrue(button("✓ Lower back tight").exists)

        // the seeded key is fake → Gemini rejects it → back on check-in
        // with the error shown and the answers intact
        let build = button("Build session")
        app.swipeUp()
        app.swipeUp()
        build.tap()
        XCTAssertTrue(app.staticTexts["error"].waitForExistence(timeout: 90))
        XCTAssertTrue(text("Check-in").exists)
        XCTAssertEqual(readiness, "17")
        XCTAssertTrue(button("Poor").isSelected)

        app.swipeDown()
        app.swipeDown()
        button("Back").tap()
        XCTAssertTrue(button("Start workout").waitForExistence(timeout: 5))
    }

    func testBackdatedQuickCardioDoesNotBecomeLastSession() {
        XCTAssertTrue(button("Run").waitForExistence(timeout: 10))

        // today's run
        logCardio(open: "Run", title: "Log a run", save: "🏃 Save run", minutes: "30", day: nil)

        // yesterday's ride — logged later, but must sort after today's run
        logCardio(open: "Ride", title: "Log a ride", save: "🚴 Save ride", minutes: "45", day: "Yesterday")
        button("Log").tap()
        let run = text("Running"), ride = text("Cycling")
        XCTAssertTrue(run.waitForExistence(timeout: 5))
        XCTAssertTrue(ride.exists)
        XCTAssertLessThan(run.frame.minY, ride.frame.minY, "backdated ride sorted above today's run")
        XCTAssertTrue(text("RPE 6").exists)
    }

    /// Workout → Finish on the seeded in-progress Push session: log a set,
    /// rest timer + skip, plate math, then finish with a PR and save.
    func testWorkoutLogsSetsRestsAndFinishesWithPR() {
        app.terminate()
        app.launchEnvironment["COACH_DEBUG_SCREEN"] = "workout"
        app.launch()
        XCTAssertTrue(text("PUSH").waitForExistence(timeout: 10))
        XCTAssertTrue(text("0/8 sets").exists)
        // each exercise logs the right way: walk = min/km, stretch = tick-off
        XCTAssertTrue(app.staticTexts["30s each side"].exists)
        XCTAssertTrue(app.staticTexts["km"].exists, "cardio row shows min/km inputs")

        // first set of Flat Dumbbell Press: 25kg × 10 (seeded history: 24×11)
        let weight = app.textFields.element(boundBy: 0)
        weight.tap()
        weight.typeText("25")
        let reps = app.textFields.element(boundBy: 1)
        reps.tap()
        reps.typeText("10")
        text("PUSH").tap() // dismiss the keyboard

        // plate math follows the typed weight
        app.buttons["Plate breakdown for 25kg"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["25kg → 20kg bar + 2.5 per side"].waitForExistence(timeout: 3))

        // ticking the set starts the rest timer
        app.buttons["Set 1"].firstMatch.tap()
        XCTAssertTrue(text("1/8 sets").waitForExistence(timeout: 3))
        XCTAssertTrue(app.descendants(matching: .any)["rest-bar"].waitForExistence(timeout: 3))
        button("Skip").tap()
        XCTAssertTrue(app.descendants(matching: .any)["rest-bar"].waitForNonExistence(timeout: 3))

        // effort cycles '' → easy
        app.buttons["Effort for set 1: not rated"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Effort for set 1: easy"].firstMatch.waitForExistence(timeout: 3))

        // finish: 25kg beats the seeded 24kg → PR banner
        let finish = button("Finish session")
        for _ in 0..<8 where !finish.isHittable { app.swipeUp() }
        finish.tap()
        XCTAssertTrue(text("How did it go?").waitForExistence(timeout: 5))
        XCTAssertTrue(text("🏆 New record").exists)
        button("Save session").tap()

        // back home, today's session done
        XCTAssertTrue(button("Plan another session").waitForExistence(timeout: 10))
        XCTAssertTrue(text("Completed").exists, "today's focus shows the finished session")
    }

    /// Log → detail → edit a set → add a past workout → delete a session.
    func testHistoryDetailEditAddPastAndDelete() {
        XCTAssertTrue(button("Log").waitForExistence(timeout: 10))
        button("Log").tap()

        // the seeded Push session (Flat Dumbbell Press 24kg×11)
        XCTAssertTrue(text("Log").waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Flat Dumbbell Press: 24kg×11"].exists)

        // detail: sets + the coach debrief
        app.staticTexts["Flat Dumbbell Press: 24kg×11"].tap()
        XCTAssertTrue(text("24kg×11").waitForExistence(timeout: 5))
        XCTAssertTrue(text("Coach debrief").exists)
        button("Back").tap()

        // edit in place: 11 reps → 12
        XCTAssertTrue(app.buttons["Session options"].firstMatch.waitForExistence(timeout: 5))
        app.buttons["Session options"].firstMatch.tap()
        button("Edit").tap()
        let reps = app.textFields.element(boundBy: 1)
        XCTAssertTrue(reps.waitForExistence(timeout: 5))
        reps.doubleTap() // select "11" so typing replaces it
        reps.typeText("12")
        button("Save changes").tap()
        XCTAssertTrue(app.staticTexts["Flat Dumbbell Press: 24kg×12"].waitForExistence(timeout: 5),
                      "card shows: \(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Flat'")).allElementsBoundByIndex.map(\.label))")

        // add a past workout
        button("Add past workout").tap()
        XCTAssertTrue(text("Past workout").waitForExistence(timeout: 5))
        let name = app.textFields["Exercise"]
        name.tap()
        name.typeText("Bench Press")
        let kg = app.textFields.matching(NSPredicate(format: "placeholderValue == 'kg'")).firstMatch
        kg.tap()
        kg.typeText("60")
        let r = app.textFields.matching(NSPredicate(format: "placeholderValue == 'reps'")).firstMatch
        r.tap()
        r.typeText("8")
        text("Past workout").tap()
        let save = button("Save")
        for _ in 0..<6 where !save.isHittable { app.swipeUp() }
        save.tap()
        XCTAssertTrue(app.staticTexts["Bench Press: 60kg×8"].waitForExistence(timeout: 5))

        // delete the edited Push session
        let pushCard = app.staticTexts["Flat Dumbbell Press: 24kg×12"]
        XCTAssertTrue(pushCard.exists)
        app.buttons.matching(NSPredicate(format: "label == %@", "Session options")).element(boundBy: 1).tap() // newest first: [past, Push]
        button("Delete").tap()
        button("Delete").tap()
        XCTAssertTrue(pushCard.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Bench Press: 60kg×8"].exists, "the other session stays")
    }

    /// Settings sections open; the coach chat opens from anywhere and
    /// surfaces the (fake-key) error; Records and Progress render.
    func testSettingsChatRecordsAndProgress() {
        XCTAssertTrue(button("Log").waitForExistence(timeout: 10))

        // coach chat from the floating button
        app.buttons["Ask the coach"].tap()
        XCTAssertTrue(app.buttons["Close chat"].waitForExistence(timeout: 5))
        let ask = app.textFields["Ask the coach…"]
        ask.tap()
        ask.typeText("how heavy should warm-up sets be?")
        app.buttons["Send"].tap()
        XCTAssertTrue(text("how heavy should warm-up sets be?").waitForExistence(timeout: 5), "message bubble shows")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'key'")).firstMatch.waitForExistence(timeout: 30),
                      "the seeded fake key → an error the user can act on")
        app.buttons["Close chat"].tap()

        // records + progress open and show the seeded session
        button("Records").tap()
        XCTAssertTrue(text("Personal records").waitForExistence(timeout: 5))
        XCTAssertTrue(text("Flat Dumbbell Press").exists)
        button("Progress").tap()
        XCTAssertTrue(text("Log two sessions to unlock charts.").waitForExistence(timeout: 5))

        // settings: sections expand
        app.buttons["Settings"].tap()
        XCTAssertTrue(text("About COACH").waitForExistence(timeout: 5))
        XCTAssertTrue(button("Sign out").exists)
        text("Barbell & plate setup").tap()
        XCTAssertTrue(button("Save gym setup").waitForExistence(timeout: 3))
        button("Close").tap()
        text("Send feedback").tap()
        XCTAssertTrue(button("Send feedback").waitForExistence(timeout: 3))
        button("Close").tap()

        // notifications + profile open from the tab header
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Notifications'")).firstMatch.tap()
        XCTAssertTrue(button("Close").waitForExistence(timeout: 3))
        button("Close").tap()
        button("Profile").tap()
        XCTAssertTrue(text("Display name").waitForExistence(timeout: 3))
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
