import XCTest
@testable import CoachApp

/// COACH Pro: with an active entitlement every Gemini request goes to the
/// COACH server (functions/index.js) with the sign-in token — never to
/// Google with a key — and the server's refusals stop the model ladder.
@MainActor
final class ProTests: XCTestCase {
    final class Stub: URLProtocol {
        static var requests: [URLRequest] = []
        static var bodies: [String] = []
        static var status = 200
        override class func canInit(with request: URLRequest) -> Bool {
            ["europe-west2-heath-9a322.cloudfunctions.net", "generativelanguage.googleapis.com"].contains(request.url?.host ?? "")
        }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            Self.requests.append(request)
            var data = Data()
            if let s = request.httpBodyStream {
                s.open()
                let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: 65536)
                while s.hasBytesAvailable { let n = s.read(buf, maxLength: 65536); if n <= 0 { break }; data.append(buf, count: n) }
                buf.deallocate()
                s.close()
            }
            Self.bodies.append(String(data: data, encoding: .utf8) ?? "")
            let plan = #"{"sessionType":"Push","title":"Server plan","estTimeMin":40,"exercises":[{"name":"Bench Press","sets":3,"reps":"8"}]}"#
            let body: Any = Self.status == 200
                ? ["candidates": [["content": ["parts": [["text": plan]]], "finishReason": "STOP"]]]
                : ["error": ["code": Self.status, "message": "COACH Pro isn’t active on this account."]]
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: try! JSONSerialization.data(withJSONObject: body))
            client?.urlProtocolDidFinishLoading(self)
        }
        override func stopLoading() {}
    }

    override func setUp() {
        Cloud.shared.offline = true
        Cloud.shared.setSharedGeminiKey("")
        AIConsent.set(true)
        Cloud.shared.debugIdToken = "test-id-token"
        Stub.requests = []
        Stub.bodies = []
        Stub.status = 200
        URLProtocol.registerClass(Stub.self)
    }

    override func tearDown() {
        URLProtocol.unregisterClass(Stub.self)
        Cloud.shared.debugSetPro([:])
        Cloud.shared.debugIdToken = nil
        Cloud.shared.setSharedGeminiKey("stub-key")
    }

    func testNoKeyAndNoProMeansNoAI() async {
        XCTAssertFalse(Cloud.shared.aiReady)
        do { _ = try await Gemini.generateWorkoutPlan(checkin: Checkin(), history: []); XCTFail() } catch {}
        XCTAssertTrue(Stub.requests.isEmpty)
    }

    func testProSendsEveryRequestThroughTheServer() async throws {
        Cloud.shared.debugSetPro(["pro": .bool(true), "expiresAt": .number(Date().addingTimeInterval(86400).timeIntervalSince1970 * 1000)])
        XCTAssertTrue(Cloud.shared.aiReady, "Pro works without a key")
        let plan = try await Gemini.generateWorkoutPlan(checkin: Checkin(), history: [])
        XCTAssertEqual(plan.title, "Server plan")
        let req = try XCTUnwrap(Stub.requests.first)
        XCTAssertEqual(req.url?.absoluteString, "https://europe-west2-heath-9a322.cloudfunctions.net/coach")
        XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer test-id-token")
        XCTAssertNil(req.value(forHTTPHeaderField: "X-goog-api-key"), "no key leaves the phone")
        XCTAssertTrue(Stub.bodies[0].contains("\"model\":\"gemini-3.5-flash\""))
        XCTAssertTrue(Stub.bodies[0].contains("\"contents\""))
    }

    func testServerRefusalStopsTheModelLadder() async {
        Cloud.shared.debugSetPro(["pro": .bool(true)])
        Stub.status = 402
        do {
            _ = try await Gemini.generateWorkoutPlan(checkin: Checkin(), history: [])
            XCTFail("should refuse")
        } catch {
            XCTAssertEqual(error.localizedDescription, "COACH Pro isn’t active on this account.")
        }
        XCTAssertEqual(Stub.requests.count, 1, "not retried on the other models")
    }

    func testExpiredProFallsBackToTheKey() {
        Cloud.shared.debugSetPro(["pro": .bool(true), "expiresAt": .number(1000)])
        XCTAssertFalse(Cloud.shared.proActive)
    }
}
