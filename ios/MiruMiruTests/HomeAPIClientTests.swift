import XCTest
@testable import MiruMiru

final class HomeAPIClientTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        super.tearDown()
    }

    func testFetchProfileDecodesMemberProfile() async throws {
        let client = makeClient(
            tokenStore: tokenStore(),
            expectedPath: "/api/v1/members/me",
            responseBody: """
            {
              "success": true,
              "data": {
                "memberId": 1,
                "email": "test@tokyo.ac.jp",
                "nickname": "test-user",
                "university": {
                  "universityId": 10,
                  "name": "The University of Tokyo",
                  "emailDomain": "tokyo.ac.jp"
                },
                "major": {
                  "majorId": 20,
                  "code": "CS",
                  "name": "Computer Science"
                }
              },
              "error": null
            }
            """
        )

        let profile = try await client.fetchProfile()
        XCTAssertEqual(profile.memberId, 1)
        XCTAssertEqual(profile.email, "test@tokyo.ac.jp")
        XCTAssertEqual(profile.nickname, "test-user")
        XCTAssertEqual(profile.universityName, "The University of Tokyo")
        XCTAssertEqual(profile.majorCode, "CS")
    }

    func testFetchSemestersDecodesSemesterList() async throws {
        let client = makeClient(
            tokenStore: tokenStore(),
            expectedPath: "/api/v1/semesters",
            responseBody: """
            {
              "success": true,
              "data": [
                { "id": 20261, "academicYear": 2026, "term": "SPRING" }
              ],
              "error": null
            }
            """
        )

        let semesters = try await client.fetchSemesters()
        XCTAssertEqual(semesters, [HomeSemester(id: 20261, academicYear: 2026, term: "SPRING")])
    }

    func testFetchTimetableDecodesEmptyTimetable() async throws {
        let client = makeClient(
            tokenStore: tokenStore(),
            expectedPath: "/api/v1/timetables/me?semesterId=20261",
            responseBody: """
            {
              "success": true,
              "data": {
                "timetableId": null,
                "semester": { "id": 20261, "academicYear": 2026, "term": "SPRING" },
                "lectures": []
              },
              "error": null
            }
            """
        )

        let timetable = try await client.fetchTimetable(semesterId: 20261)
        XCTAssertNil(timetable.timetableId)
        XCTAssertEqual(timetable.semester, HomeSemester(id: 20261, academicYear: 2026, term: "SPRING"))
        XCTAssertTrue(timetable.lectures.isEmpty)
    }

    func testFetchScheduleItemsEncodesISODateRangeAndDecodesResponse() async throws {
        let from = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-03-17T15:00:00Z"))
        let to = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-03-18T15:00:00Z"))
        let client = makeScheduleClient { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.path, "/api/v1/schedule-items")

            let components = try XCTUnwrap(URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false))
            let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).compactMap { item in
                item.value.map { (item.name, $0) }
            })
            XCTAssertEqual(query["from"], "2026-03-17T15:00:00.000Z")
            XCTAssertEqual(query["to"], "2026-03-18T15:00:00.000Z")
            XCTAssertEqual(query["status"], "all")

            return self.scheduleListResponseBody()
        }

        let items = try await client.fetchScheduleItems(from: from, to: to, status: .all)

        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].itemId, 101)
        XCTAssertEqual(items[0].lectureName, "Algorithms")
        XCTAssertEqual(items[0].type, .assignment)
        XCTAssertEqual(items[0].dueAt, ISO8601DateFormatter().date(from: "2026-03-18T05:30:00Z"))
    }

    func testCreateScheduleItemPostsOptionalLectureAndISODeadline() async throws {
        let dueAt = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-03-18T05:30:00Z"))
        let client = makeScheduleClient { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/api/v1/schedule-items")
            let payload = try self.jsonBody(for: request)
            XCTAssertEqual(payload["lectureId"] as? Int, 44)
            XCTAssertEqual(payload["type"] as? String, "ASSIGNMENT")
            XCTAssertEqual(payload["title"] as? String, "Problem set 4")
            XCTAssertEqual(payload["memo"] as? String, "Questions 1-8")
            XCTAssertEqual(payload["dueAt"] as? String, "2026-03-18T05:30:00.000Z")
            XCTAssertEqual(payload["completed"] as? Bool, false)
            return self.scheduleResponseBody()
        }

        let item = try await client.createScheduleItem(
            HomeScheduleItemInput(
                lectureId: 44,
                type: .assignment,
                title: "Problem set 4",
                memo: "Questions 1-8",
                dueAt: dueAt,
                completed: false
            )
        )

        XCTAssertEqual(item.itemId, 101)
    }

    func testUpdateAndCompletionUseDedicatedMethods() async throws {
        var methods: [String] = []
        var paths: [String] = []
        let client = makeScheduleClient { request in
            methods.append(try XCTUnwrap(request.httpMethod))
            paths.append(try XCTUnwrap(request.url?.path))
            let payload = try self.jsonBody(for: request)
            if request.httpMethod == "PATCH" {
                XCTAssertEqual(payload["completed"] as? Bool, true)
            }
            return self.scheduleResponseBody(completed: request.httpMethod == "PATCH")
        }

        _ = try await client.updateScheduleItem(
            itemId: 101,
            input: HomeScheduleItemInput(
                lectureId: nil,
                type: .memo,
                title: "Bring calculator",
                memo: nil,
                dueAt: nil,
                completed: false
            )
        )
        let completed = try await client.setScheduleItemCompletion(itemId: 101, completed: true)

        XCTAssertEqual(methods, ["PUT", "PATCH"])
        XCTAssertEqual(
            paths,
            ["/api/v1/schedule-items/101", "/api/v1/schedule-items/101/completion"]
        )
        XCTAssertTrue(completed.completed)
    }

    func testDeleteScheduleItemUsesDeleteRoute() async throws {
        let client = makeScheduleClient { request in
            XCTAssertEqual(request.httpMethod, "DELETE")
            XCTAssertEqual(request.url?.path, "/api/v1/schedule-items/101")
            return """
            {
              "success": true,
              "data": null,
              "error": null
            }
            """
        }

        try await client.deleteScheduleItem(itemId: 101)
    }

    func testFetchProfileMapsFailedReissueToInvalidSession() async {
        let store = tokenStore()
        MockURLProtocol.requestHandler = { request in
            let path = try XCTUnwrap(request.url?.path)

            if path == "/api/v1/members/me" {
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 401,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )!
                return (response, Data("""
                {
                  "success": false,
                  "data": null,
                  "error": {
                    "code": "AUTH_001",
                    "message": "Unauthorized",
                    "detail": null
                  }
                }
                """.utf8))
            }

            if path == "/api/v1/auth/reissue" {
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 401,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )!
                return (response, Data("""
                {
                  "success": false,
                  "data": null,
                  "error": {
                    "code": "AUTH_001",
                    "message": "Unauthorized",
                    "detail": null
                  }
                }
                """.utf8))
            }

            XCTFail("Unexpected path: \(path)")
            throw URLError(.badURL)
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let apiClient = APIClient(
            environment: AppEnvironment(
                apiBaseURL: URL(string: "http://localhost")!,
                enforcesAcademicSuffixValidation: true
            ),
            session: session
        )
        let client = HomeAPIClient(apiClient: apiClient, tokenStore: store)

        do {
            _ = try await client.fetchProfile()
            XCTFail("Expected invalid session")
        } catch let error as HomeClientError {
            XCTAssertEqual(error, .invalidSession)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testFetchProfileReissuesExpiredAccessTokenAndRetriesRequest() async throws {
        let store = tokenStore()
        var membersMeCalls = 0

        MockURLProtocol.requestHandler = { request in
            let path = try XCTUnwrap(request.url?.path)
            let response: HTTPURLResponse
            let body: Data

            switch path {
            case "/api/v1/members/me":
                membersMeCalls += 1
                if membersMeCalls == 1 {
                    XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer preview-access")
                    response = HTTPURLResponse(
                        url: request.url!,
                        statusCode: 401,
                        httpVersion: nil,
                        headerFields: ["Content-Type": "application/json"]
                    )!
                    body = Data("""
                    {
                      "success": false,
                      "data": null,
                      "error": {
                        "code": "AUTH_001",
                        "message": "Unauthorized",
                        "detail": null
                      }
                    }
                    """.utf8)
                } else {
                    XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer refreshed-access")
                    response = HTTPURLResponse(
                        url: request.url!,
                        statusCode: 200,
                        httpVersion: nil,
                        headerFields: ["Content-Type": "application/json"]
                    )!
                    body = Data("""
                    {
                      "success": true,
                      "data": {
                        "memberId": 1,
                        "email": "test@tokyo.ac.jp",
                        "nickname": "test-user",
                        "university": {
                          "universityId": 10,
                          "name": "The University of Tokyo",
                          "emailDomain": "tokyo.ac.jp"
                        },
                        "major": {
                          "majorId": 20,
                          "code": "CS",
                          "name": "Computer Science"
                        }
                      },
                      "error": null
                    }
                    """.utf8)
                }
            case "/api/v1/auth/reissue":
                let requestBody = try XCTUnwrap(request.httpBody)
                let decoded = try JSONDecoder().decode(ReissueRequest.self, from: requestBody)
                XCTAssertEqual(decoded, ReissueRequest(accessToken: "preview-access", refreshToken: "preview-refresh"))
                response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )!
                body = Data("""
                {
                  "success": true,
                  "data": {
                    "accessToken": "refreshed-access",
                    "refreshToken": "refreshed-refresh"
                  },
                  "error": null
                }
                """.utf8)
            default:
                XCTFail("Unexpected path: \(path)")
                throw URLError(.badURL)
            }

            return (response, body)
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let apiClient = APIClient(
            environment: AppEnvironment(
                apiBaseURL: URL(string: "http://localhost")!,
                enforcesAcademicSuffixValidation: true
            ),
            session: session
        )
        let client = HomeAPIClient(apiClient: apiClient, tokenStore: store)

        let profile = try await client.fetchProfile()

        XCTAssertEqual(membersMeCalls, 2)
        XCTAssertEqual(profile.nickname, "test-user")
        XCTAssertEqual(store.storedSession, TokenPair(accessToken: "refreshed-access", refreshToken: "refreshed-refresh"))
    }

    func testConcurrentClientsShareSingleReissueFlow() async throws {
        let store = tokenStore()
        let state = ConcurrentRefreshState()

        MockURLProtocol.requestHandler = { request in
            let path = try XCTUnwrap(request.url?.path)
            let response: HTTPURLResponse
            let body: Data

            switch path {
            case "/api/v1/members/me":
                let authorization = request.value(forHTTPHeaderField: "Authorization")
                if authorization == "Bearer preview-access" {
                    state.recordInitialMemberRequest()
                    response = HTTPURLResponse(
                        url: request.url!,
                        statusCode: 401,
                        httpVersion: nil,
                        headerFields: ["Content-Type": "application/json"]
                    )!
                    body = Data("""
                    {
                      "success": false,
                      "data": null,
                      "error": {
                        "code": "AUTH_001",
                        "message": "Unauthorized",
                        "detail": null
                      }
                    }
                    """.utf8)
                } else {
                    XCTAssertEqual(authorization, "Bearer refreshed-access")
                    state.recordRetriedMemberRequest()
                    response = HTTPURLResponse(
                        url: request.url!,
                        statusCode: 200,
                        httpVersion: nil,
                        headerFields: ["Content-Type": "application/json"]
                    )!
                    body = Data("""
                    {
                      "success": true,
                      "data": {
                        "memberId": 1,
                        "email": "test@tokyo.ac.jp",
                        "nickname": "test-user",
                        "university": {
                          "universityId": 10,
                          "name": "The University of Tokyo",
                          "emailDomain": "tokyo.ac.jp"
                        },
                        "major": {
                          "majorId": 20,
                          "code": "CS",
                          "name": "Computer Science"
                        }
                      },
                      "error": null
                    }
                    """.utf8)
                }
            case "/api/v1/auth/reissue":
                state.recordReissueRequest()
                let requestBody = try XCTUnwrap(request.httpBody)
                let decoded = try JSONDecoder().decode(ReissueRequest.self, from: requestBody)
                XCTAssertEqual(decoded, ReissueRequest(accessToken: "preview-access", refreshToken: "preview-refresh"))
                response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )!
                body = Data("""
                {
                  "success": true,
                  "data": {
                    "accessToken": "refreshed-access",
                    "refreshToken": "refreshed-refresh"
                  },
                  "error": null
                }
                """.utf8)
            default:
                XCTFail("Unexpected path: \(path)")
                throw URLError(.badURL)
            }

            return (response, body)
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let apiClient = APIClient(
            environment: AppEnvironment(
                apiBaseURL: URL(string: "http://localhost")!,
                enforcesAcademicSuffixValidation: true
            ),
            session: session
        )
        let sharedExecutor = AuthorizedRequestExecutor(apiClient: apiClient, tokenStore: store)
        let firstClient = HomeAPIClient(
            apiClient: apiClient,
            tokenStore: store,
            authorizedExecutor: sharedExecutor
        )
        let secondClient = HomeAPIClient(
            apiClient: apiClient,
            tokenStore: store,
            authorizedExecutor: sharedExecutor
        )

        async let firstProfile = firstClient.fetchProfile()
        async let secondProfile = secondClient.fetchProfile()
        let profiles = try await [firstProfile, secondProfile]

        XCTAssertEqual(profiles.map(\.nickname), ["test-user", "test-user"])
        XCTAssertEqual(state.initialMemberRequestCount, 2)
        XCTAssertEqual(state.reissuedRequestCount, 1)
        XCTAssertEqual(state.retriedMemberRequestCount, 2)
        XCTAssertEqual(store.storedSession, TokenPair(accessToken: "refreshed-access", refreshToken: "refreshed-refresh"))
    }

    func testFetchProfileMapsReissuePersistenceFailureToInvalidSession() async {
        let store = tokenStore()
        store.shouldFailOnSave = true
        var membersMeCalls = 0

        MockURLProtocol.requestHandler = { request in
            let path = try XCTUnwrap(request.url?.path)
            let response: HTTPURLResponse
            let body: Data

            switch path {
            case "/api/v1/members/me":
                membersMeCalls += 1
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer preview-access")
                response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 401,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )!
                body = Data("""
                {
                  "success": false,
                  "data": null,
                  "error": {
                    "code": "AUTH_001",
                    "message": "Unauthorized",
                    "detail": null
                  }
                }
                """.utf8)
            case "/api/v1/auth/reissue":
                response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )!
                body = Data("""
                {
                  "success": true,
                  "data": {
                    "accessToken": "refreshed-access",
                    "refreshToken": "refreshed-refresh"
                  },
                  "error": null
                }
                """.utf8)
            default:
                XCTFail("Unexpected path: \(path)")
                throw URLError(.badURL)
            }

            return (response, body)
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let apiClient = APIClient(
            environment: AppEnvironment(
                apiBaseURL: URL(string: "http://localhost")!,
                enforcesAcademicSuffixValidation: true
            ),
            session: session
        )
        let client = HomeAPIClient(apiClient: apiClient, tokenStore: store)

        do {
            _ = try await client.fetchProfile()
            XCTFail("Expected invalid session")
        } catch let error as HomeClientError {
            XCTAssertEqual(error, .invalidSession)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertEqual(membersMeCalls, 1)
        XCTAssertNil(store.storedSession)
    }

    private func makeClient(
        tokenStore: TokenStore,
        expectedPath: String,
        responseBody: String,
        statusCode: Int = 200
    ) -> HomeAPIClient {
        MockURLProtocol.requestHandler = { request in
            XCTAssertTrue(request.url?.absoluteString.contains(expectedPath) == true)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer preview-access")

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
        let apiClient = APIClient(
            environment: AppEnvironment(
                apiBaseURL: URL(string: "http://localhost")!,
                enforcesAcademicSuffixValidation: true
            ),
            session: session
        )
        return HomeAPIClient(apiClient: apiClient, tokenStore: tokenStore)
    }

    private func makeScheduleClient(
        response: @escaping (URLRequest) throws -> String
    ) -> HomeAPIClient {
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer preview-access")
            let responseBody = try response(request)
            let httpResponse = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (httpResponse, Data(responseBody.utf8))
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let apiClient = APIClient(
            environment: AppEnvironment(
                apiBaseURL: URL(string: "http://localhost")!,
                enforcesAcademicSuffixValidation: true
            ),
            session: session
        )
        return HomeAPIClient(apiClient: apiClient, tokenStore: tokenStore())
    }

    private func jsonBody(for request: URLRequest) throws -> [String: Any] {
        let body: Data
        if let httpBody = request.httpBody {
            body = httpBody
        } else if let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }

            var data = Data()
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 1_024)
            defer { buffer.deallocate() }
            while stream.hasBytesAvailable {
                let count = stream.read(buffer, maxLength: 1_024)
                guard count > 0 else { break }
                data.append(buffer, count: count)
            }
            body = data
        } else {
            throw XCTSkip("Request body was unavailable")
        }

        return try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
    }

    private func scheduleResponseBody(completed: Bool = false) -> String {
        """
        {
          "success": true,
          "data": {
            "itemId": 101,
            "lectureId": 44,
            "lectureName": "Algorithms",
            "type": "ASSIGNMENT",
            "title": "Problem set 4",
            "memo": "Questions 1-8",
            "dueAt": "2026-03-18T05:30:00Z",
            "completed": \(completed),
            "createdAt": "2026-03-17T03:00:00.123Z",
            "updatedAt": "2026-03-17T03:10:00Z"
          },
          "error": null
        }
        """
    }

    private func scheduleListResponseBody() -> String {
        """
        {
          "success": true,
          "data": [
            {
              "itemId": 101,
              "lectureId": 44,
              "lectureName": "Algorithms",
              "type": "ASSIGNMENT",
              "title": "Problem set 4",
              "memo": "Questions 1-8",
              "dueAt": "2026-03-18T05:30:00Z",
              "completed": false,
              "createdAt": "2026-03-17T03:00:00.123Z",
              "updatedAt": "2026-03-17T03:10:00Z"
            }
          ],
          "error": null
        }
        """
    }

    private func tokenStore() -> InMemoryTokenStore {
        let store = InMemoryTokenStore()
        store.storedSession = TokenPair(accessToken: "preview-access", refreshToken: "preview-refresh")
        return store
    }
}

final class MessagesAPIClientTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        super.tearDown()
    }

    func testCreateRoomEncodesPartnerMemberId() async throws {
        let client = makeMessagesClient(
            expectedPath: "/api/v1/message-rooms",
            expectedMethod: "POST",
            responseBody: """
            {
              "success": true,
              "data": {
                "roomId": 101,
                "postId": 2001,
                "member1Id": 1,
                "member2Id": 22,
                "roomTitle": "Study Post",
                "counterpartDisplayName": "Anonymous 2",
                "isAnon1": false,
                "isAnon2": true,
                "created": true
              },
              "error": null
            }
            """
        ) { [self] request in
            let body = try self.requestBodyData(for: request)
            let decoded = try JSONSerialization.jsonObject(with: body) as? [String: Any]
            XCTAssertEqual(decoded?["postId"] as? Int, 2001)
            XCTAssertEqual(decoded?["requesterIsAnonymous"] as? Bool, false)
            XCTAssertEqual(decoded?["partnerMemberId"] as? Int, 22)
        }

        let response = try await client.createRoom(postId: 2001, requesterIsAnonymous: false, partnerMemberId: 22)
        XCTAssertEqual(response.member2Id, 22)
    }

    func testBlockMemberPostsExpectedPayload() async throws {
        let client = makeMessagesClient(
            expectedPath: "/api/v1/chat/blocks",
            expectedMethod: "POST",
            responseBody: """
            {
              "success": true,
              "data": {
                "targetMemberId": 22,
                "blocked": true,
                "created": true
              },
              "error": null
            }
            """
        ) { [self] request in
            let body = try self.requestBodyData(for: request)
            let decoded = try JSONSerialization.jsonObject(with: body) as? [String: Any]
            XCTAssertEqual(decoded?["targetMemberId"] as? Int, 22)
        }

        try await client.blockMember(targetMemberId: 22)
    }

    func testUnblockMemberCallsDeletePath() async throws {
        let client = makeMessagesClient(
            expectedPath: "/api/v1/chat/blocks/22",
            expectedMethod: "DELETE",
            responseBody: """
            {
              "success": true,
              "data": {
                "targetMemberId": 22,
                "unblocked": true
              },
              "error": null
            }
            """
        )

        try await client.unblockMember(targetMemberId: 22)
    }

    func testCreateRoomMapsBlockedConversation() async {
        let client = makeMessagesClient(
            expectedPath: "/api/v1/message-rooms",
            expectedMethod: "POST",
            responseBody: """
            {
              "success": false,
              "data": null,
              "error": {
                "code": "AUTH_002",
                "message": "chat_blocked_between_members",
                "detail": null
              }
            }
            """,
            statusCode: 403
        )

        do {
            _ = try await client.createRoom(postId: 2001, requesterIsAnonymous: false, partnerMemberId: 22)
            XCTFail("Expected blocked conversation")
        } catch let error as MessagesClientError {
            XCTAssertEqual(error, .blockedConversation)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    private func makeMessagesClient(
        expectedPath: String,
        expectedMethod: String,
        responseBody: String,
        statusCode: Int = 200,
        requestValidator: ((URLRequest) throws -> Void)? = nil
    ) -> MessagesAPIClient {
        MockURLProtocol.requestHandler = { request in
            XCTAssertTrue(request.url?.absoluteString.contains(expectedPath) == true)
            XCTAssertEqual(request.httpMethod, expectedMethod)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer preview-access")
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
        let apiClient = APIClient(
            environment: AppEnvironment(
                apiBaseURL: URL(string: "http://localhost")!,
                enforcesAcademicSuffixValidation: true
            ),
            session: session
        )
        let store = InMemoryTokenStore()
        store.storedSession = TokenPair(accessToken: "preview-access", refreshToken: "preview-refresh")
        return MessagesAPIClient(apiClient: apiClient, tokenStore: store)
    }

    private func requestBodyData(for request: URLRequest) throws -> Data {
        if let body = request.httpBody {
            return body
        }

        guard let stream = request.httpBodyStream else {
            throw XCTSkip("Request body not available")
        }

        stream.open()
        defer { stream.close() }

        var data = Data()
        let bufferSize = 1024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }

        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: bufferSize)
            if read < 0 {
                break
            }
            if read == 0 {
                break
            }
            data.append(buffer, count: read)
        }

        return data
    }
}

private final class ConcurrentRefreshState: @unchecked Sendable {
    private let lock = NSLock()
    private var _initialMemberRequestCount = 0
    private var _retriedMemberRequestCount = 0
    private var _reissuedRequestCount = 0

    var initialMemberRequestCount: Int {
        lock.withLock { _initialMemberRequestCount }
    }

    var retriedMemberRequestCount: Int {
        lock.withLock { _retriedMemberRequestCount }
    }

    var reissuedRequestCount: Int {
        lock.withLock { _reissuedRequestCount }
    }

    func recordInitialMemberRequest() {
        lock.withLock { _initialMemberRequestCount += 1 }
    }

    func recordRetriedMemberRequest() {
        lock.withLock { _retriedMemberRequestCount += 1 }
    }

    func recordReissueRequest() {
        lock.withLock { _reissuedRequestCount += 1 }
    }
}
