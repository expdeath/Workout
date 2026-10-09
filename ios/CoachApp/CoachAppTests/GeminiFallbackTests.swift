import XCTest
@testable import CoachApp

/// Model fallback without touching the network: a URLProtocol stub
/// answers every Gemini request. A rate-limited model must hand over to
/// the next one immediately (each model has its own quota) instead of
/// waiting and retrying the same one.
final class GeminiFallbackTests: XCTestCase {
    final class Stub: URLProtocol {
        static var requested: [String] = []
        static var rateLimited: Set<String> = []
        override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "generativelanguage.googleapis.com" }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            let model = request.url!.lastPathComponent.components(separatedBy: ":").first ?? ""
            Self.requested.append(model)
            let limited = Self.rateLimited.contains(model)
            let plan = #"{"sessionType":"Push","title":"Stub push","estTimeMin":45,"exercises":[{"name":"Bench Press","sets":3,"reps":"8-10","rpe":"8","rest":"90s"}]}"#
            let body: Any = limited
                ? ["error": ["code": 429, "message": "Quota exceeded. Please retry in 30s."]]
                : ["candidates": [["content": ["parts": [["text": plan]]], "finishReason": "STOP"]]]
            let data = try! JSONSerialization.data(withJSONObject: body)
            let resp = HTTPURLResponse(url: request.url!, statusCode: limited ? 429 : 200, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        }
        override func stopLoading() {}
    }

    override func setUp() {
        URLProtocol.registerClass(Stub.self)
        Stub.requested = []
        Cloud.shared.offline = true
        Cloud.shared.setSharedGeminiKey("stub-key")
        AIConsent.set(true)
    }

    override func tearDown() {
        URLProtocol.unregisterClass(Stub.self)
    }

    func testRateLimitedPrimarySwitchesToNextModelAtOnce() async throws {
        Stub.rateLimited = ["gemini-3.5-flash"]
        let started = Date()
        let plan = try await Gemini.generateWorkoutPlan(checkin: Checkin(), history: [])
        XCTAssertEqual(plan.title, "Stub push")
        XCTAssertEqual(Stub.requested, ["gemini-3.5-flash", "gemini-3.1-flash-lite"])
        XCTAssertLessThan(Date().timeIntervalSince(started), 5, "no 30–45s wait before switching")
    }

    func testOverloadedStillSwitchesAndHealthyPrimaryIsUsedFirst() async throws {
        Stub.rateLimited = []
        _ = try await Gemini.generateWorkoutPlan(checkin: Checkin(), history: [])
        XCTAssertEqual(Stub.requested, ["gemini-3.5-flash"])
    }
}
