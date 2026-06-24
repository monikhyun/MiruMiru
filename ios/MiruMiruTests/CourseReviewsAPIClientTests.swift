import XCTest
@testable import MiruMiru

final class CourseReviewsAPIClientTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        super.tearDown()
    }

    func testFetchReviewFeedDecodesItems() async throws {
        let client = makeClient(
            expectedPath: "/api/v1/course-reviews?page=0&size=20",
            expectedMethod: "GET",
            responseBody: """
            {
              "success": true,
              "data": {
                "items": [
                  {
                    "reviewId": 1,
                    "targetId": 10,
                    "courseId": 100,
                    "courseCode": "ECON301",
                    "courseName": "Advanced Microeconomics",
                    "professorDisplayName": "Prof. Tanaka",
                    "displayName": "Advanced Microeconomics: Prof. Tanaka",
                    "overallRating": 8,
                    "professorRating": 9,
                    "difficulty": 3,
                    "workload": 4,
                    "wouldTakeAgain": true,
                    "content": "Great class",
                    "professorContent": "Helpful professor",
                    "academicYear": 2026,
                    "term": "SPRING",
                    "isMine": false,
                    "createdAt": "2026-03-24T10:30:00Z",
                    "updatedAt": "2026-03-24T10:30:00Z"
                  }
                ],
                "page": 0,
                "size": 20,
                "totalElements": 1,
                "totalPages": 1,
                "hasNext": false
              },
              "error": null
            }
            """
        )

        let page = try await client.fetchReviewFeed(page: 0, size: 20)
        XCTAssertEqual(page.items.first?.target.courseName, "Advanced Microeconomics")
        XCTAssertEqual(page.items.first?.target.targetId, 10)
        XCTAssertEqual(page.items.first?.overallRating, 8)
        XCTAssertEqual(page.items.first?.professorRating, 9)
        XCTAssertEqual(page.items.first?.professorContent, "Helpful professor")
        XCTAssertEqual(page.totalElements, 1)
    }

    func testCreateReviewPostsExpectedBody() async throws {
        let client = makeClient(
            expectedPath: "/api/v1/course-review-targets/12/reviews",
            expectedMethod: "POST",
            responseBody: """
            {
              "success": true,
              "data": { "reviewId": 99 },
              "error": null
            }
            """
        ) { request in
            let body = try self.requestBodyData(for: request)
            let decoded = try JSONDecoder().decode(CourseReviewUpsertRequest.self, from: body)
            XCTAssertEqual(
                decoded,
                CourseReviewUpsertRequest(
                    academicYear: 2026,
                    term: "SPRING",
                    overallRating: 9,
                    professorRating: 8,
                    difficulty: 3,
                    workload: 4,
                    wouldTakeAgain: true,
                    content: "Loved it",
                    professorContent: "Clear lectures"
                )
            )
        }

        let reviewId = try await client.createReview(
            targetId: 12,
            request: CourseReviewUpsertRequest(
                academicYear: 2026,
                term: "SPRING",
                overallRating: 9,
                professorRating: 8,
                difficulty: 3,
                workload: 4,
                wouldTakeAgain: true,
                content: "Loved it",
                professorContent: "Clear lectures"
            )
        )

        XCTAssertEqual(reviewId, 99)
    }

    private func makeClient(
        expectedPath: String,
        expectedMethod: String,
        responseBody: String,
        statusCode: Int = 200,
        requestValidator: ((URLRequest) throws -> Void)? = nil
    ) -> CourseReviewsAPIClient {
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, expectedMethod)
            XCTAssertTrue(request.url?.absoluteString.contains(expectedPath) == true)
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
        let tokenStore = InMemoryTokenStore()
        tokenStore.storedSession = TokenPair(accessToken: "preview-access", refreshToken: "preview-refresh")
        return CourseReviewsAPIClient(apiClient: apiClient, tokenStore: tokenStore)
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
            if read <= 0 {
                break
            }
            data.append(buffer, count: read)
        }

        return data
    }
}
