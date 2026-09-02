import XCTest
@testable import CoachApp

/// Confirms invite codes decode with the exact same base64url + JSON
/// encoding scripts/make-invite.js produces (Buffer.from(json).toString
/// ('base64url')), so existing beta invite codes keep working unmodified.
final class AccountTests: XCTestCase {
    func testParseInviteCode_decodesNodeBase64UrlEncoding() throws {
        // Generated once via:
        //   node -e "console.log(Buffer.from(JSON.stringify({v:1,
        //     name:'TestUser', repo:'expdeath/coach-data-test',
        //     ghToken:'github_pat_FAKE123', geminiKey:'AIzaFAKE456'}))
        //     .toString('base64url'))"
        let code = "eyJ2IjoxLCJuYW1lIjoiVGVzdFVzZXIiLCJyZXBvIjoiZXhwZGVhdGgvY29hY2gtZGF0YS10ZXN0IiwiZ2hUb2tlbiI6ImdpdGh1Yl9wYXRfRkFLRTEyMyIsImdlbWluaUtleSI6IkFJemFGQUtFNDU2In0"

        let acct = try Account.parseInviteCode(code)
        XCTAssertEqual(acct.name, "TestUser")
        XCTAssertEqual(acct.repo, "expdeath/coach-data-test")
        XCTAssertEqual(acct.ghToken, "github_pat_FAKE123")
        XCTAssertEqual(acct.geminiKey, "AIzaFAKE456")
    }

    func testParseInviteCode_acceptsFullMagicLinkNotJustBareCode() throws {
        // Pasting the whole https://…/#invite=<code> link (as sent over
        // WhatsApp/Signal per docs/accounts.md) must work directly here,
        // since — unlike the website — this app has no separate
        // hash-parsing auto-redeem path to fall back on.
        let code = "eyJ2IjoxLCJuYW1lIjoiVGVzdFVzZXIiLCJyZXBvIjoiZXhwZGVhdGgvY29hY2gtZGF0YS10ZXN0IiwiZ2hUb2tlbiI6ImdpdGh1Yl9wYXRfRkFLRTEyMyIsImdlbWluaUtleSI6IkFJemFGQUtFNDU2In0"
        let link = "https://expdeath.github.io/Workout/#invite=\(code)"

        let acct = try Account.parseInviteCode(link)
        XCTAssertEqual(acct.name, "TestUser")
        XCTAssertEqual(acct.ghToken, "github_pat_FAKE123")
    }

    func testParseInviteCode_acceptsAmpersandInviteParam() throws {
        let code = "eyJ2IjoxLCJuYW1lIjoiVGVzdFVzZXIiLCJyZXBvIjoiZXhwZGVhdGgvY29hY2gtZGF0YS10ZXN0IiwiZ2hUb2tlbiI6ImdpdGh1Yl9wYXRfRkFLRTEyMyIsImdlbWluaUtleSI6IkFJemFGQUtFNDU2In0"
        let link = "https://expdeath.github.io/Workout/?ref=share&invite=\(code)"
        let acct = try Account.parseInviteCode(link)
        XCTAssertEqual(acct.name, "TestUser")
    }

    func testParseInviteCode_emptyThrows() {
        XCTAssertThrowsError(try Account.parseInviteCode(""))
    }

    func testParseInviteCode_garbageThrows() {
        XCTAssertThrowsError(try Account.parseInviteCode("not-a-real-code!!"))
    }

    func testParseInviteCode_incompleteThrows() {
        // Valid base64url JSON but missing required fields.
        let code = Data("{\"name\":\"X\"}".utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        XCTAssertThrowsError(try Account.parseInviteCode(code))
    }
}
