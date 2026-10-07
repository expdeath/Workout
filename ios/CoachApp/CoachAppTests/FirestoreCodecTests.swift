import XCTest
@testable import CoachApp

/// FirestoreCodec must produce exactly what src/db/firestoreCodec.js
/// produces (both apps share the documents) and round-trip any JSON.
final class FirestoreCodecTests: XCTestCase {
    /// Simulates the trip through Firestore: numbers and booleans come
    /// back as NSNumber (JSONSerialization hands them back the same way).
    private func throughFirestore(_ v: Any) -> Any {
        let data = try! JSONSerialization.data(withJSONObject: ["v": v], options: [.fragmentsAllowed])
        return (try! JSONSerialization.jsonObject(with: data) as! [String: Any])["v"]!
    }

    private func json(_ s: String) -> JSONValue {
        try! JSONDecoder().decode(JSONValue.self, from: Data(s.utf8))
    }

    func testNestedArraysAreWrappedLikeTheWebCodec() {
        // a session's log: [[set, set], [set]]
        let enc = FirestoreCodec.encode(json(#"{"log":[[{"weight":"60"}],[]]}"#)) as! [String: Any]
        let log = enc["log"] as! [Any]
        let first = log[0] as! [String: Any]
        XCTAssertEqual((first["__a"] as! [Any]).count, 1, "inner array wrapped in { __a: [...] }")
        XCTAssertNotNil((log[1] as! [String: Any])["__a"])
    }

    func testBadKeysUseTheEscapedMapForm() {
        let enc = FirestoreCodec.encode(json(#"{"":1,"__x__":2}"#)) as! [String: Any]
        XCTAssertEqual(Array(enc.keys), ["__m"])
    }

    func testRoundTripOfEdgeCases() {
        let v = json(#"{"a":[[1,[2]],[]],"":1,"__x__":{"__a":[3]},"n":null,"s":"é/ü","e":{},"t":true,"f":false,"one":1,"half":0.5,"big":1789570663885}"#)
        XCTAssertEqual(FirestoreCodec.decode(throughFirestore(FirestoreCodec.encode(v))), v)
    }

    func testBooleansAndNumbersStayDistinct() {
        // NSNumber carries both — 1 must not come back as true, nor true as 1
        let v = json(#"{"done":true,"sets":1,"zero":0,"no":false}"#)
        XCTAssertEqual(FirestoreCodec.decode(throughFirestore(FirestoreCodec.encode(v))), v)
    }

    func testWholeNumbersAreWrittenAsIntegers() {
        let enc = FirestoreCodec.encode(.number(1789570663885)) as! Int64
        XCTAssertEqual(enc, 1789570663885)
        XCTAssertEqual(FirestoreCodec.encode(.number(51.77)) as? Double, 51.77)
    }

    func testDocIdsMatchTheWebCodec() {
        XCTAssertEqual(FirestoreCodec.docId("2026-10-07#1784468740277"), "2026-10-07#1784468740277")
        XCTAssertEqual(FirestoreCodec.docId("a/b%c"), "a%2Fb%25c")
        XCTAssertEqual(FirestoreCodec.docId(""), "%")
        XCTAssertEqual(FirestoreCodec.docId(".."), "%..")
        XCTAssertEqual(FirestoreCodec.docId("__name__"), "%__name__")
        XCTAssertEqual(FirestoreCodec.eventDocId(Event(ts: 1, iso: "2026-10-07T06:06:52.123Z", type: "app_open")),
                       "2026-10-07T06:06:52.123Z|app_open")
    }

    func testSessionDocumentRoundTripsLosslessly() throws {
        let raw = #"{"id":"2026-08-01#1","date":"2026-08-01","plan":{"sessionType":"Push","exercises":[{"name":"Bench","rpe":8,"extra":"kept"}]},"log":[[{"weight":"60","done":true,"hr":151}]],"futureKey":[1,[2]]}"#
        let s = try JSONDecoder().decode(Session.self, from: Data(raw.utf8))
        let doc = throughFirestore(try FirestoreCodec.document(s)) as! [String: Any]
        let back = try FirestoreCodec.model(Session.self, from: doc)
        XCTAssertEqual(try JSONValue.encoding(back), json(raw), "unknown keys and odd types survive the database")
    }
}
