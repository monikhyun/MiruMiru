import Foundation

final class HomeAPIClient: HomeClientProtocol, @unchecked Sendable {
    private let apiClient: APIClient
    private let authorizedExecutor: AuthorizedRequestExecutor
    private let encoder = JSONEncoder()

    init(
        apiClient: APIClient,
        tokenStore: TokenStore,
        authorizedExecutor: AuthorizedRequestExecutor? = nil
    ) {
        self.apiClient = apiClient
        self.authorizedExecutor = authorizedExecutor ?? AuthorizedRequestExecutor(apiClient: apiClient, tokenStore: tokenStore)
    }

    func fetchProfile() async throws -> HomeMemberProfile {
        let payload: ProfileResponse = try await requestPayload(
            path: "/api/v1/members/me",
            cachePolicy: RequestCachePolicy(
                key: APICacheKey.sharedMemberMe,
                maxAge: APICacheTTL.memberProfile
            )
        )
        return payload.toDomain()
    }

    func fetchSemesters() async throws -> [HomeSemester] {
        let payload: [SemesterResponse] = try await requestPayload(
            path: "/api/v1/semesters",
            cachePolicy: RequestCachePolicy(
                key: APICacheKey.sharedSemesters,
                maxAge: APICacheTTL.semesters
            )
        )
        return payload.map(\.toDomain)
    }

    func fetchTimetable(semesterId: Int64) async throws -> HomeTimetable {
        let payload: TimetableResponse = try await requestPayload(
            path: "/api/v1/timetables/me?semesterId=\(semesterId)",
            cachePolicy: RequestCachePolicy(
                key: APICacheKey.sharedTimetable(semesterId: semesterId),
                maxAge: APICacheTTL.timetable
            )
        )
        return payload.toDomain()
    }

    func fetchHotPosts() async throws -> [HotPostSummary] {
        let payload: [HotPostResponse] = try await requestPayload(
            path: "/api/v1/posts/hot",
            cachePolicy: RequestCachePolicy(
                key: APICacheKey.sharedHotPosts,
                maxAge: APICacheTTL.hotPosts
            )
        )
        return payload.map(\.toDomain)
    }

    func fetchScheduleItems(
        from: Date,
        to: Date,
        status: HomeScheduleItemStatus
    ) async throws -> [HomeScheduleItem] {
        var components = URLComponents()
        components.path = "/api/v1/schedule-items"
        components.queryItems = [
            URLQueryItem(name: "from", value: Self.iso8601String(from: from)),
            URLQueryItem(name: "to", value: Self.iso8601String(from: to)),
            URLQueryItem(name: "status", value: status.rawValue)
        ]

        let payload: [ScheduleItemResponse] = try await requestPayload(
            path: components.string ?? "/api/v1/schedule-items"
        )
        return try payload.map { try $0.toDomain() }
    }

    func createScheduleItem(_ input: HomeScheduleItemInput) async throws -> HomeScheduleItem {
        let body = try encoder.encode(ScheduleItemRequest(input: input))
        let payload: ScheduleItemResponse = try await sendPayload(
            path: "/api/v1/schedule-items",
            method: .post,
            body: body
        )
        return try payload.toDomain()
    }

    func updateScheduleItem(itemId: Int64, input: HomeScheduleItemInput) async throws -> HomeScheduleItem {
        let body = try encoder.encode(ScheduleItemRequest(input: input))
        let payload: ScheduleItemResponse = try await sendPayload(
            path: "/api/v1/schedule-items/\(itemId)",
            method: .put,
            body: body
        )
        return try payload.toDomain()
    }

    func setScheduleItemCompletion(itemId: Int64, completed: Bool) async throws -> HomeScheduleItem {
        let body = try encoder.encode(CompletionRequest(completed: completed))
        let payload: ScheduleItemResponse = try await sendPayload(
            path: "/api/v1/schedule-items/\(itemId)/completion",
            method: .patch,
            body: body
        )
        return try payload.toDomain()
    }

    func deleteScheduleItem(itemId: Int64) async throws {
        try await sendEmpty(
            path: "/api/v1/schedule-items/\(itemId)",
            method: .delete
        )
    }

    func invalidateCache() async {
        await authorizedExecutor.invalidateCache(key: APICacheKey.sharedMemberMe)
        await authorizedExecutor.invalidateCache(key: APICacheKey.sharedSemesters)
        await authorizedExecutor.invalidateCache(key: APICacheKey.sharedHotPosts)
        await authorizedExecutor.invalidateCache(prefix: APICacheKey.sharedTimetablePrefix)
    }

    private func requestPayload<Response: Decodable>(
        path: String,
        cachePolicy: RequestCachePolicy? = nil
    ) async throws -> Response {
        do {
            let data = try await authorizedExecutor.get(
                path: path,
                cachePolicy: cachePolicy
            )
            let envelope = try apiClient.decode(APIResponseEnvelope<Response>.self, from: data)
            guard envelope.success, let payload = envelope.data else {
                throw HomeClientError.unexpected
            }
            return payload
        } catch let error as APIClientError {
            throw map(apiError: error)
        } catch let error as HomeClientError {
            throw error
        } catch {
            throw HomeClientError.unexpected
        }
    }

    private func sendPayload<Response: Decodable>(
        path: String,
        method: HTTPMethod,
        body: Data
    ) async throws -> Response {
        do {
            let (data, _) = try await authorizedExecutor.send(
                path: path,
                method: method,
                body: body
            )
            let envelope = try apiClient.decode(APIResponseEnvelope<Response>.self, from: data)
            guard envelope.success, let payload = envelope.data else {
                throw HomeClientError.unexpected
            }
            return payload
        } catch let error as APIClientError {
            throw map(apiError: error)
        } catch let error as HomeClientError {
            throw error
        } catch {
            throw HomeClientError.unexpected
        }
    }

    private func sendEmpty(
        path: String,
        method: HTTPMethod
    ) async throws {
        do {
            let (data, _) = try await authorizedExecutor.send(path: path, method: method)
            let envelope = try apiClient.decode(APIResponseEnvelope<EmptyPayload>.self, from: data)
            guard envelope.success else {
                throw HomeClientError.unexpected
            }
        } catch let error as APIClientError {
            throw map(apiError: error)
        } catch let error as HomeClientError {
            throw error
        } catch {
            throw HomeClientError.unexpected
        }
    }

    private func map(apiError: APIClientError) -> HomeClientError {
        switch apiError {
        case .transport:
            return .network
        case let .server(statusCode, _):
            if statusCode == 401 {
                return .invalidSession
            }
            return .unexpected
        default:
            return .unexpected
        }
    }

    private static func iso8601String(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }

    private static func parseISO8601(_ value: String) -> Date? {
        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractionalFormatter.date(from: value) {
            return date
        }

        return ISO8601DateFormatter().date(from: value)
    }
}

private extension HomeAPIClient {
    struct ScheduleItemRequest: Encodable {
        let lectureId: Int64?
        let type: HomeScheduleItemType
        let title: String
        let memo: String?
        let dueAt: String?
        let completed: Bool

        init(input: HomeScheduleItemInput) {
            lectureId = input.lectureId
            type = input.type
            title = input.title
            memo = input.memo
            dueAt = input.dueAt.map(HomeAPIClient.iso8601String)
            completed = input.completed
        }
    }

    struct CompletionRequest: Encodable {
        let completed: Bool
    }

    struct ScheduleItemResponse: Decodable {
        let itemId: Int64
        let lectureId: Int64?
        let lectureName: String?
        let type: HomeScheduleItemType
        let title: String
        let memo: String?
        let dueAt: String?
        let completed: Bool
        let createdAt: String
        let updatedAt: String

        func toDomain() throws -> HomeScheduleItem {
            guard let createdAtDate = HomeAPIClient.parseISO8601(createdAt),
                  let updatedAtDate = HomeAPIClient.parseISO8601(updatedAt) else {
                throw HomeClientError.unexpected
            }

            let dueAtDate: Date?
            if let dueAt {
                guard let parsedDueAt = HomeAPIClient.parseISO8601(dueAt) else {
                    throw HomeClientError.unexpected
                }
                dueAtDate = parsedDueAt
            } else {
                dueAtDate = nil
            }

            return HomeScheduleItem(
                itemId: itemId,
                lectureId: lectureId,
                lectureName: lectureName,
                type: type,
                title: title,
                memo: memo,
                dueAt: dueAtDate,
                completed: completed,
                createdAt: createdAtDate,
                updatedAt: updatedAtDate
            )
        }
    }

    struct ProfileResponse: Decodable {
        let memberId: Int64
        let email: String
        let nickname: String
        let university: UniversityResponse
        let major: MajorResponse

        func toDomain() -> HomeMemberProfile {
            HomeMemberProfile(
                memberId: memberId,
                email: email,
                nickname: nickname,
                universityName: university.name,
                universityEmailDomain: university.emailDomain,
                majorCode: major.code,
                majorName: major.name
            )
        }
    }

    struct UniversityResponse: Decodable {
        let universityId: Int64
        let name: String
        let emailDomain: String
    }

    struct MajorResponse: Decodable {
        let majorId: Int64
        let code: String
        let name: String
    }

    struct SemesterResponse: Decodable {
        let id: Int64
        let academicYear: Int
        let term: String

        var toDomain: HomeSemester {
            HomeSemester(
                id: id,
                academicYear: academicYear,
                term: term
            )
        }
    }

    struct TimetableResponse: Decodable {
        let timetableId: Int64?
        let semester: SemesterResponse
        let lectures: [LectureResponse]

        func toDomain() -> HomeTimetable {
            HomeTimetable(
                timetableId: timetableId,
                semester: semester.toDomain,
                lectures: lectures.map(\.toDomain)
            )
        }
    }

    struct LectureResponse: Decodable {
        let id: Int64
        let code: String
        let name: String
        let professor: String
        let schedules: [ScheduleResponse]

        var toDomain: HomeLecture {
            HomeLecture(
                id: id,
                code: code,
                name: name,
                professor: professor,
                schedules: schedules.map(\.toDomain)
            )
        }
    }

    struct ScheduleResponse: Decodable {
        let dayOfWeek: String
        let startTime: String
        let endTime: String
        let location: String

        var toDomain: HomeLectureSchedule {
            HomeLectureSchedule(
                dayOfWeek: dayOfWeek,
                startTime: startTime,
                endTime: endTime,
                location: location
            )
        }
    }

    struct HotPostResponse: Decodable {
        let postId: Int64
        let boardId: Int64
        let boardCode: String
        let boardName: String
        let title: String
        let authorDisplayName: String
        let isAnonymous: Bool
        let likeCount: Int
        let commentCount: Int
        let createdAt: String

        var toDomain: HotPostSummary {
            HotPostSummary(
                id: postId,
                boardId: boardId,
                boardCode: boardCode,
                boardName: boardName,
                title: title,
                authorDisplayName: authorDisplayName,
                isAnonymous: isAnonymous,
                likeCount: likeCount,
                commentCount: commentCount,
                createdAt: createdAt
            )
        }
    }
}
