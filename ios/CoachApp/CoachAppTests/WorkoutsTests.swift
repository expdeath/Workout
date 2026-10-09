import XCTest
@testable import CoachApp

/// Saved workouts (Models/SavedWorkout.swift) — same rules as
/// src/utils/workouts.js: keep-exact holds the coach to the written
/// workout, add-ons go on the end, the schedule follows the weekday,
/// and the backup file carries the library.
@MainActor
final class WorkoutsTests: XCTestCase {
    final class Stub: URLProtocol {
        static var lastBody = ""
        static var reply = ""
        override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "generativelanguage.googleapis.com" }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            if let stream = request.httpBodyStream {
                stream.open()
                var data = Data()
                let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: 65536)
                while stream.hasBytesAvailable { let n = stream.read(buf, maxLength: 65536); if n <= 0 { break }; data.append(buf, count: n) }
                buf.deallocate()
                stream.close()
                Self.lastBody = String(data: data, encoding: .utf8) ?? ""
            } else if let b = request.httpBody {
                Self.lastBody = String(data: b, encoding: .utf8) ?? ""
            }
            let body = try! JSONSerialization.data(withJSONObject: ["candidates": [["content": ["parts": [["text": Self.reply]]], "finishReason": "STOP"]]])
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        }
        override func stopLoading() {}
    }

    override func setUp() {
        Cloud.shared.offline = true
        Cloud.shared.setSharedGeminiKey("stub-key")
        for k in Cloud.shared.stateKeys() where k.hasPrefix("workout-") { Cloud.shared.setState(k, nil) }
        URLProtocol.registerClass(Stub.self)
    }

    override func tearDown() { URLProtocol.unregisterClass(Stub.self) }

    private let todayWD = Calendar.current.component(.weekday, from: Date()) - 1

    private func upperA(adapt: Bool = false) -> SavedWorkout {
        SavedWorkout(name: "Upper A", source: "trainer", trainer: "Sam", adapt: adapt, days: [todayWD], exercises: [
            .init(name: "Bench Press", sets: 4, reps: "6"),
            .init(name: "Barbell Row", sets: 3, reps: "8", weight: "60kg"),
        ])
    }

    func testDecodesTheWebAppsShape() throws {
        let json = #"{"id":"abc1","name":"Daily core","kind":"addon","source":"trainer","trainer":"Sam","notes":"","adapt":false,"days":[],"exercises":[{"name":"Plank","sets":3,"reps":"45s","weight":"","rest":"30s","notes":""}],"createdAt":1791520416446,"updatedAt":1791520416446}"#
        let w = try JSONDecoder().decode(SavedWorkout.self, from: Data(json.utf8))
        XCTAssertTrue(w.isAddOn)
        XCTAssertEqual(w.exercises.first?.reps, "45s")
        XCTAssertEqual(Workouts.daysLabel(w), "Every day")
    }

    func testSaveListScheduleDelete() {
        let s = Workouts.save(upperA())
        let a = Workouts.save(SavedWorkout(name: "Daily core", kind: "addon", exercises: [.init(name: "Plank", sets: 3, reps: "45s")]))
        Workouts.save(SavedWorkout(name: "Lower B", days: [(todayWD + 1) % 7], exercises: [.init(name: "Back Squat")]))
        XCTAssertFalse(s.id.isEmpty)
        XCTAssertEqual(Workouts.list().map(\.name), ["Lower B", "Upper A", "Daily core"], "sessions first, then add-ons")
        let today = Workouts.scheduledFor()
        XCTAssertEqual(today.sessions.map(\.name), ["Upper A"])
        XCTAssertEqual(today.addOns.map(\.name), ["Daily core"])
        Workouts.delete(a.id)
        XCTAssertNil(Workouts.get(a.id))
    }

    func testKeepExactHoldsTheCoachToTheWrittenWorkout() {
        let coach = Plan(sessionType: "Full Body", title: "Coach version", exercises: [
            .init(name: "Back Squat", sets: 5, reps: "5", suggestedWeight: "90kg"),
            .init(name: "Bench Press", sets: 2, reps: "10", rpe: "7", notes: "Pause on chest", suggestedWeight: "72.5kg"),
        ])
        let p = Workouts.enforceExact(coach, upperA(), [])
        XCTAssertEqual(p.title, "Upper A")
        XCTAssertEqual(p.exercises.map(\.name), ["Bench Press", "Barbell Row"])
        XCTAssertEqual(p.exercises[0].sets, 4)
        XCTAssertEqual(p.exercises[0].reps, "6")
        XCTAssertEqual(p.exercises[0].suggestedWeight, "72.5kg", "the coach fills a weight the trainer left blank")
        XCTAssertEqual(p.exercises[1].suggestedWeight, "60kg", "the trainer's weight wins")
        XCTAssertEqual(p.exercises[0].notes, "Pause on chest")
    }

    func testWithoutTheCoachWeightsComeFromHistory() {
        let plan = Plan(sessionType: "Push", exercises: [.init(name: "Bench Press", sets: 3, reps: "8-10")])
        let prior = Session(id: "p1", date: "2026-01-01", startedAt: 0, checkin: nil, plan: plan,
                            log: [[SetLog(weight: "60", reps: "10", done: true), SetLog(weight: "60", reps: "10", done: true)]], finished: true)
        var w = upperA()
        w.exercises[0].reps = "8-10"
        let p = Workouts.templateToPlan(w, [prior])
        XCTAssertEqual(p.exercises[0].suggestedWeight, "62.5kg", "topped the range last time → +2.5kg")
        XCTAssertEqual(p.exercises[1].suggestedWeight, "60kg")
        XCTAssertTrue(p.reasoning.contains("Sam"))
    }

    func testAddOnsGoOnTheEnd() {
        let core = SavedWorkout(name: "Daily core", kind: "addon", exercises: [.init(name: "Plank", sets: 3, reps: "45s"), .init(name: "Dead Bug", sets: 2, reps: "10")])
        let p = Workouts.appendAddOns(Workouts.templateToPlan(upperA(), []), [core], [])
        XCTAssertEqual(p.exercises.map(\.name), ["Bench Press", "Barbell Row", "Plank", "Dead Bug"])
        XCTAssertTrue(p.exercises[2].notes.hasPrefix("Add-on · Daily core"))
    }

    func testPromptTellsTheCoachWhichMode() {
        XCTAssertTrue(Gemini.buildUserMessage(Checkin(), [], template: upperA()).contains("Use EXACTLY these exercises"))
        XCTAssertTrue(Gemini.buildUserMessage(Checkin(), [], template: upperA(adapt: true)).contains("ADAPTED TO TODAY"))
        XCTAssertTrue(Gemini.buildUserMessage(Checkin(), []).contains("Decide the right session for today"))
    }

    func testCoachBuildsWorkoutsFromTextAndPhoto() async throws {
        Stub.reply = #"{"message":"Built two.","workouts":[{"name":"Lower B","kind":"session","days":["Mon"],"notes":"","exercises":[{"name":"Back Squat","sets":4,"reps":"6","weight":"85kg","rest":"3 min","notes":""}]},{"name":"Daily core","kind":"addon","days":[],"notes":"","exercises":[{"name":"Plank","sets":3,"reps":"45s","weight":"","rest":"","notes":""}]}]}"#
        let res = try await Gemini.buildWorkouts(text: "Day B Monday: squat 4x6 85kg", imageJPEG: Data([0xFF, 0xD8, 0xFF]), source: "trainer", history: [])
        XCTAssertEqual(res.workouts.map(\.name), ["Lower B", "Daily core"])
        XCTAssertEqual(res.workouts[0].days, [1])
        XCTAssertTrue(res.workouts[1].isAddOn)
        XCTAssertEqual(res.message, "Built two.")
        XCTAssertTrue(Stub.lastBody.contains("inline_data"), "the photo is sent to the coach")
        XCTAssertTrue(Stub.lastBody.contains("Transcribe it faithfully"))
    }

    func testBackupCarriesTheLibraryAndSwitches() throws {
        var b = Backup()
        let w1 = try JSONValue.encoding(SavedWorkout(id: "b", name: "B"))
        let w2 = try JSONValue.encoding(SavedWorkout(id: "a", name: "A"))
        b.workouts = [w1, w2]
        b.prefs = .object(["restSound": .bool(false)])
        let n = GitHubSync.normalizeBackup(b)
        let round = try JSONDecoder().decode(Backup.self, from: JSONEncoder().encode(n))
        XCTAssertEqual(round.workouts.count, 2)
        if case .object(let o) = round.workouts[0], case .string(let id)? = o["id"] { XCTAssertEqual(id, "a", "sorted by id") } else { XCTFail() }
        XCTAssertEqual(round.prefs, .object(["restSound": .bool(false)]))
        let empty = String(data: try JSONEncoder().encode(GitHubSync.normalizeBackup(Backup())), encoding: .utf8)!
        XCTAssertFalse(empty.contains("workouts"), "no key when there's nothing to carry — same as the web")
        XCTAssertFalse(empty.contains("prefs"))
    }

    func testSwitchesDefaultOnAndSave() {
        Cloud.shared.setState("prefs", nil)
        XCTAssertTrue(Prefs.isOn("restSound"))
        Prefs.set("restSound", false)
        XCTAssertFalse(Prefs.isOn("restSound"))
        XCTAssertTrue(Prefs.isOn("debrief"))
        Cloud.shared.setState("prefs", nil)
    }
}
