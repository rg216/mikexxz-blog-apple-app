import Foundation
import Testing

@testable import BlogKit

struct AppAuthRequestTests {
  @Test func pkceChallengeMatchesRFC7636() {
    // RFC 7636 附录 B 的测试向量
    let request = AppAuthRequest(verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk", state: "s")
    #expect(request.challenge == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
  }

  @Test func generatedValuesHaveTheLengthsTheSiteAccepts() {
    let request = AppAuthRequest.make()
    #expect(request.verifier.count == 43)
    #expect(request.challenge.count == 43)
    #expect(request.state.count >= 16)
    #expect(request.verifier.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" })
  }

  @Test func authorizeURL() throws {
    let request = AppAuthRequest(verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk", state: "state-0123456789abcdef")
    let url = request.authorizeURL(site: URL(string: "https://blog.example")!, deviceName: "Mike 的 iPhone")
    let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
    #expect(components.path == "/admin/authorize-app")
    let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
    #expect(query["challenge"] == request.challenge)
    #expect(query["state"] == "state-0123456789abcdef")
    #expect(query["device"] == "Mike 的 iPhone")
    #expect(query["redirect_uri"] == "mikexxz-blog://auth/callback")
  }

  @Test func callbackParsing() throws {
    let request = AppAuthRequest(verifier: "v", state: "abc")
    #expect(try request.code(from: URL(string: "mikexxz-blog://auth/callback?code=xyz&state=abc")!) == "xyz")
    #expect(throws: AppAuthRequest.CallbackError.invalid) { try request.code(from: URL(string: "mikexxz-blog://auth/callback?code=xyz&state=other")!) }
    #expect(throws: AppAuthRequest.CallbackError.denied) { try request.code(from: URL(string: "mikexxz-blog://auth/callback?error=access_denied&state=abc")!) }
    #expect(throws: AppAuthRequest.CallbackError.invalid) { try request.code(from: URL(string: "evil://auth/callback?code=xyz&state=abc")!) }
  }
}

struct AdminModelTests {
  @Test func postInputEncodesOnlyGivenFields() throws {
    let json = try String(decoding: AdminClient.encoder.encode(PostInput(title: "T", coverImage: .some(nil))), as: UTF8.self)
    let object = try #require(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
    #expect(Set(object.keys) == ["title", "coverImage"])
    #expect(object["coverImage"] is NSNull)
  }

  @Test func streamEvents() throws {
    func decode(_ line: String) throws -> TranslationStreamEvent {
      try BlogClient.decoder.decode(TranslationStreamEvent.self, from: Data(line.utf8))
    }
    #expect(try decode(#"{"type":"ping"}"#) == .ping)
    #expect(try decode(#"{"type":"delta","text":"Hi"}"#) == .delta("Hi"))
    let usage = #"{"inputTokens":1,"outputTokens":2,"cacheReadInputTokens":3,"cacheCreationInputTokens":4}"#
    #expect(
      try decode(#"{"type":"done","text":"T","stopReason":"end_turn","model":"m","usage":\#(usage)}"#)
        == .done(text: "T", stopReason: "end_turn", model: "m", usage: TranslationUsage(inputTokens: 1, outputTokens: 2, cacheReadInputTokens: 3, cacheCreationInputTokens: 4)))
    #expect(try decode(#"{"type":"error","code":"internal_error","message":"x"}"#) == .error(code: "internal_error", message: "x"))
    #expect(try decode(#"{"type":"future"}"#) == .unknown)
  }

  @Test func combineModelNames() {
    #expect(ModelNames.combine(["a", "b", "a", " "]) == "a, b")
    let long = String(repeating: "x", count: 60)
    #expect(ModelNames.combine([long, long + "y"]) == long + ", …")
    #expect(ModelNames.combine([String(repeating: "z", count: 120)]).utf16.count == 100)
    let squeezed = ModelNames.combine([String(repeating: "z", count: 120), "b"])
    #expect(squeezed.utf16.count <= 100)
    #expect(squeezed.hasSuffix(", …"))
  }

  @Test func serverErrorsKeepTheMessageAndIssues() {
    let body = #"{"error":{"code":"validation_error","message":"请求参数无效","issues":[{"path":"slug","message":"slug 已被占用"}]}}"#
    let error = AdminClient.serverError(status: 400, data: Data(body.utf8))
    #expect(error.message == "请求参数无效")
    #expect(error.issue(for: "slug") == "slug 已被占用")
    #expect(AdminClient.serverError(status: 502, data: Data("<html>".utf8)).message.contains("502"))
  }

  @Test func missingTagTranslations() throws {
    let tag = try BlogClient.decoder.decode(
      AdminTag.self, from: Data(#"{"id":1,"slug":"a","name":"甲","translations":{"en":"A","ja":" "},"postCount":0,"publishedCount":0}"#.utf8))
    #expect(tag.missingTranslations == [.ja])
  }
}
