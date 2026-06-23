import XCTest
@testable import MiruMiru

final class AuthAPIClientTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        super.tearDown()
    }

    func testLoginDecodesTokenPair() async throws {
        let client = makeClient(
            expectedPath: "/api/v1/auth/login",
            expectedMethod: "POST",
            responseBody: """
            {
              "success": true,
              "data": {
                "accessToken": "access",
                "refreshToken": "refresh"
              },
              "error": null
            }
            """
        )

        let tokenPair = try await client.login(email: "test@tokyo.ac.jp", password: "password123!")
        XCTAssertEqual(tokenPair, TokenPair(accessToken: "access", refreshToken: "refresh"))
    }

    func testReissuePostsExpectedBodyAndDecodesTokenPair() async throws {
        let client = makeClient(
            expectedPath: "/api/v1/auth/reissue",
            expectedMethod: "POST",
            responseBody: """
            {
              "success": true,
              "data": {
                "accessToken": "new-access",
                "refreshToken": "new-refresh"
              },
              "error": null
            }
            """
        ) { request in
            let body = try XCTUnwrap(request.httpBody)
            let decoded = try JSONDecoder().decode(ReissueRequest.self, from: body)
            XCTAssertEqual(decoded, ReissueRequest(accessToken: "old-access", refreshToken: "old-refresh"))
        }

        let tokenPair = try await client.reissue(accessToken: "old-access", refreshToken: "old-refresh")
        XCTAssertEqual(tokenPair, TokenPair(accessToken: "new-access", refreshToken: "new-refresh"))
    }

    func testSendEmailCodePostsExpectedBody() async throws {
        let client = makeClient(
            expectedPath: "/api/v1/auth/email/send-code",
            expectedMethod: "POST",
            responseBody: """
            {"success":true,"data":null,"error":null}
            """
        ) { request in
            let body = try XCTUnwrap(request.httpBody)
            let decoded = try JSONDecoder().decode(SendEmailCodeRequest.self, from: body)
            XCTAssertEqual(decoded, SendEmailCodeRequest(email: "user@tokyo.ac.jp"))
        }

        try await client.sendEmailCode(email: "user@tokyo.ac.jp")
    }

    func testVerifyEmailCodePostsExpectedBody() async throws {
        let client = makeClient(
            expectedPath: "/api/v1/auth/email/verify-code",
            expectedMethod: "POST",
            responseBody: """
            {"success":true,"data":null,"error":null}
            """
        ) { request in
            let body = try XCTUnwrap(request.httpBody)
            let decoded = try JSONDecoder().decode(VerifyEmailCodeRequest.self, from: body)
            XCTAssertEqual(decoded, VerifyEmailCodeRequest(email: "user@tokyo.ac.jp", code: "123456"))
        }

        try await client.verifyEmailCode(email: "user@tokyo.ac.jp", code: "123456")
    }

    func testFetchMajorsReadsQueryAndDecodesPayload() async throws {
        let client = makeClient(
            expectedPathPrefix: "/api/v1/auth/majors?email=",
            expectedMethod: "GET",
            responseBody: """
            {
              "success": true,
              "data": [
                { "majorId": 1, "code": "CS", "name": "Computer Science" },
                { "majorId": 2, "code": "MATH", "name": "Mathematics" }
              ],
              "error": null
            }
            """
        ) { request in
            let components = URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false)
            XCTAssertEqual(components?.queryItems?.first?.name, "email")
            XCTAssertEqual(components?.queryItems?.first?.value, "user@tokyo.ac.jp")
        }

        let majors = try await client.fetchMajors(email: "user@tokyo.ac.jp")
        XCTAssertEqual(
            majors,
            [
                MajorOption(majorId: 1, code: "CS", name: "Computer Science"),
                MajorOption(majorId: 2, code: "MATH", name: "Mathematics")
            ]
        )
    }

    func testVerifyNicknamePostsExpectedBody() async throws {
        let client = makeClient(
            expectedPath: "/api/v1/auth/verify-nickname",
            expectedMethod: "POST",
            responseBody: """
            {"success":true,"data":null,"error":null}
            """
        ) { request in
            let body = try XCTUnwrap(request.httpBody)
            let decoded = try JSONDecoder().decode(NicknameVerifyRequest.self, from: body)
            XCTAssertEqual(decoded, NicknameVerifyRequest(nickname: "miru"))
        }

        try await client.verifyNickname(nickname: "miru")
    }

    func testSignUpPostsExpectedBody() async throws {
        let client = makeClient(
            expectedPath: "/api/v1/auth/signup",
            expectedMethod: "POST",
            responseBody: """
            {"success":true,"data":null,"error":null}
            """
        ) { request in
            let body = try XCTUnwrap(request.httpBody)
            let decoded = try JSONDecoder().decode(SignUpRequest.self, from: body)
            XCTAssertEqual(
                decoded,
                SignUpRequest(
                    email: "user@tokyo.ac.jp",
                    password: "password123!",
                    nickname: "miru",
                    majorId: 42
                )
            )
            XCTAssertNil(decoded.avatar)
        }

        try await client.signUp(
            email: "user@tokyo.ac.jp",
            password: "password123!",
            nickname: "miru",
            majorId: 42
        )
    }

    func testMapsSignupErrorsFromServerPayload() async throws {
        let client = makeClient(
            expectedPath: "/api/v1/auth/signup",
            expectedMethod: "POST",
            responseBody: """
            {
              "success": false,
              "data": null,
              "error": {
                "code": "AUTH_004",
                "message": "error.duplicate_nickname",
                "detail": null
              }
            }
            """,
            statusCode: 409
        )

        do {
            try await client.signUp(
                email: "user@tokyo.ac.jp",
                password: "password123!",
                nickname: "miru",
                majorId: 42
            )
            XCTFail("Expected signup to fail")
        } catch let error as AuthError {
            XCTAssertEqual(error, .duplicateNickname)
        }
    }

    private func makeClient(
        expectedPath: String,
        expectedMethod: String,
        responseBody: String,
        statusCode: Int = 200,
        requestValidator: ((URLRequest) throws -> Void)? = nil
    ) -> AuthAPIClient {
        makeClient(
            expectedPathPrefix: expectedPath,
            expectedMethod: expectedMethod,
            responseBody: responseBody,
            statusCode: statusCode,
            requestValidator: requestValidator
        )
    }

    private func makeClient(
        expectedPathPrefix: String,
        expectedMethod: String,
        responseBody: String,
        statusCode: Int = 200,
        requestValidator: ((URLRequest) throws -> Void)? = nil
    ) -> AuthAPIClient {
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, expectedMethod)
            XCTAssertTrue(request.url?.absoluteString.contains(expectedPathPrefix) == true)
            try requestValidator?(request)

            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, Data(responseBody.utf8))
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let environment = AppEnvironment(
            apiBaseURL: URL(string: "http://localhost")!,
            enforcesAcademicSuffixValidation: true
        )
        let apiClient = APIClient(environment: environment, session: session)
        return AuthAPIClient(apiClient: apiClient)
    }
}

final class MockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try handler(requestWithResolvedBody)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    private var requestWithResolvedBody: URLRequest {
        guard request.httpBody == nil, let bodyStream = request.httpBodyStream else {
            return request
        }

        var resolvedRequest = request
        resolvedRequest.httpBody = Self.data(from: bodyStream)
        return resolvedRequest
    }

    private static func data(from stream: InputStream) -> Data {
        stream.open()
        defer { stream.close() }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1_024)

        while stream.hasBytesAvailable {
            let bytesRead = stream.read(&buffer, maxLength: buffer.count)
            guard bytesRead > 0 else { break }
            data.append(buffer, count: bytesRead)
        }

        return data
    }
}
