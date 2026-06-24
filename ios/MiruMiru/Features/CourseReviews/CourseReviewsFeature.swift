import Foundation
import SwiftUI

// MARK: - Models

struct CourseReviewTargetRef: Hashable, Identifiable, Sendable {
    let targetId: Int64
    let courseId: Int64
    let courseCode: String
    let courseName: String
    let professorDisplayName: String
    let displayName: String

    var id: Int64 { targetId }
}

struct CourseReviewFeedItem: Identifiable, Equatable, Sendable {
    let reviewId: Int64
    let target: CourseReviewTargetRef
    let overallRating: Int
    let professorRating: Int?
    let difficulty: Int
    let workload: Int
    let wouldTakeAgain: Bool
    let content: String
    let professorContent: String?
    let academicYear: Int
    let term: String
    let isMine: Bool
    let createdAt: String
    let updatedAt: String

    var id: Int64 { reviewId }
}

struct CourseReviewFeedPage: Equatable, Sendable {
    let items: [CourseReviewFeedItem]
    let page: Int
    let size: Int
    let totalElements: Int
    let totalPages: Int
    let hasNext: Bool
}

struct CourseReviewSummary: Equatable, Sendable {
    let target: CourseReviewTargetRef
    let reviewCount: Int
    let averageOverall: Double?
    let averageProfessor: Double?
    let averageDifficulty: Double?
    let averageWorkload: Double?
    let wouldTakeAgainRate: Double?
}

struct CourseReviewEntry: Identifiable, Equatable, Sendable {
    let reviewId: Int64
    let overallRating: Int
    let professorRating: Int?
    let difficulty: Int
    let workload: Int
    let wouldTakeAgain: Bool
    let content: String
    let professorContent: String?
    let academicYear: Int
    let term: String
    let professorDisplayName: String
    let isMine: Bool
    let createdAt: String
    let updatedAt: String

    var id: Int64 { reviewId }
}

struct CourseReviewPage: Equatable, Sendable {
    let summary: CourseReviewSummary
    let reviews: [CourseReviewEntry]
    let page: Int
    let size: Int
    let totalElements: Int
    let totalPages: Int
    let hasNext: Bool
}

struct CourseReviewUpsertRequest: Codable, Equatable, Sendable {
    let academicYear: Int
    let term: String
    let overallRating: Int
    let professorRating: Int
    let difficulty: Int
    let workload: Int
    let wouldTakeAgain: Bool
    let content: String
    let professorContent: String?
}

enum CourseReviewFeedFilter: CaseIterable, Equatable, Sendable {
    case all
    case liberalArts
    case major
    case highRating

    var title: String {
        switch self {
        case .all:
            return "All"
        case .liberalArts:
            return "Liberal Arts"
        case .major:
            return "Major"
        case .highRating:
            return "High Rating"
        }
    }
}

enum ReviewTerm: String, CaseIterable, Identifiable, Sendable {
    case spring = "SPRING"
    case fall = "FALL"

    var id: String { rawValue }

    var title: String {
        rawValue.capitalized
    }
}

enum CourseReviewsClientError: Error, Equatable {
    case invalidSession
    case reviewAlreadyExists
    case reviewNotFound
    case targetNotFound
    case network
    case unexpected
}

enum CourseReviewsFailure: Error, Equatable {
    case invalidSession
    case reviewAlreadyExists
    case reviewNotFound
    case targetNotFound
    case network
    case unexpected

    var message: String {
        switch self {
        case .invalidSession:
            return "Your session expired. Please log in again."
        case .reviewAlreadyExists:
            return "You already submitted a review for this course."
        case .reviewNotFound:
            return "We couldn't find your review."
        case .targetNotFound:
            return "This review target is no longer available."
        case .network:
            return "Unable to load course reviews right now."
        case .unexpected:
            return "Something went wrong while processing the review."
        }
    }
}

protocol CourseReviewsClientProtocol: Sendable {
    func fetchReviewFeed(page: Int, size: Int) async throws -> CourseReviewFeedPage
    func fetchReviewTargets(query: String, page: Int, size: Int) async throws -> CourseReviewTargetPage
    func fetchTargetReviews(targetId: Int64, page: Int, size: Int) async throws -> CourseReviewPage
    func fetchMyReview(targetId: Int64) async throws -> CourseReviewEntry
    func createReview(targetId: Int64, request: CourseReviewUpsertRequest) async throws -> Int64
    func updateMyReview(targetId: Int64, request: CourseReviewUpsertRequest) async throws -> Int64
    func deleteMyReview(targetId: Int64) async throws
    func invalidateCache() async
}

extension CourseReviewsClientProtocol {
    func invalidateCache() async {}
}

struct CourseReviewTargetPage: Equatable, Sendable {
    let items: [CourseReviewTargetRef]
    let page: Int
    let size: Int
    let totalElements: Int
    let totalPages: Int
    let hasNext: Bool
}

// MARK: - API Client

final class CourseReviewsAPIClient: CourseReviewsClientProtocol, @unchecked Sendable {
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

    func fetchReviewFeed(page: Int, size: Int) async throws -> CourseReviewFeedPage {
        let payload: FeedPageResponse = try await requestPayload(
            path: "/api/v1/course-reviews?page=\(page)&size=\(size)",
            cachePolicy: RequestCachePolicy(
                key: APICacheKey.reviewsFeed(page: page, size: size),
                maxAge: APICacheTTL.reviewsFeed
            )
        )
        return payload.toDomain()
    }

    func fetchReviewTargets(query: String, page: Int, size: Int) async throws -> CourseReviewTargetPage {
        let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let payload: TargetPageResponse = try await requestPayload(
            path: "/api/v1/course-review-targets?query=\(encodedQuery)&page=\(page)&size=\(size)"
        )
        return payload.toDomain()
    }

    func fetchTargetReviews(targetId: Int64, page: Int, size: Int) async throws -> CourseReviewPage {
        let payload: ReviewPageResponse = try await requestPayload(
            path: "/api/v1/course-review-targets/\(targetId)/reviews?page=\(page)&size=\(size)",
            cachePolicy: RequestCachePolicy(
                key: APICacheKey.reviewsTargetReviews(targetId: targetId, page: page, size: size),
                maxAge: APICacheTTL.reviewsDetail
            )
        )
        return payload.toDomain()
    }

    func fetchMyReview(targetId: Int64) async throws -> CourseReviewEntry {
        let payload: ReviewItemResponse = try await requestPayload(
            path: "/api/v1/course-review-targets/\(targetId)/reviews/me",
            cachePolicy: RequestCachePolicy(
                key: APICacheKey.reviewsMyReview(targetId: targetId),
                maxAge: APICacheTTL.myReview
            )
        )
        return payload.toDomain
    }

    func createReview(targetId: Int64, request: CourseReviewUpsertRequest) async throws -> Int64 {
        let body = try encoder.encode(request)
        let payload: ReviewIdResponse = try await sendPayload(
            path: "/api/v1/course-review-targets/\(targetId)/reviews",
            method: .post,
            body: body
        )
        await invalidateCache()
        return payload.reviewId
    }

    func updateMyReview(targetId: Int64, request: CourseReviewUpsertRequest) async throws -> Int64 {
        let body = try encoder.encode(request)
        let payload: ReviewIdResponse = try await sendPayload(
            path: "/api/v1/course-review-targets/\(targetId)/reviews/me",
            method: .put,
            body: body
        )
        await invalidateCache()
        return payload.reviewId
    }

    func deleteMyReview(targetId: Int64) async throws {
        try await sendEmpty(
            path: "/api/v1/course-review-targets/\(targetId)/reviews/me",
            method: .delete
        )
        await invalidateCache()
    }

    func invalidateCache() async {
        await authorizedExecutor.invalidateCache(prefix: APICacheKey.reviewsPrefix)
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
                throw CourseReviewsClientError.unexpected
            }
            return payload
        } catch let error as APIClientError {
            throw map(apiError: error)
        } catch let error as CourseReviewsClientError {
            throw error
        } catch {
            throw CourseReviewsClientError.unexpected
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
                body: body,
            )
            let envelope = try apiClient.decode(APIResponseEnvelope<Response>.self, from: data)
            guard envelope.success, let payload = envelope.data else {
                throw CourseReviewsClientError.unexpected
            }
            return payload
        } catch let error as APIClientError {
            throw map(apiError: error)
        } catch let error as CourseReviewsClientError {
            throw error
        } catch {
            throw CourseReviewsClientError.unexpected
        }
    }

    private func sendEmpty(
        path: String,
        method: HTTPMethod
    ) async throws {
        do {
            let (data, _) = try await authorizedExecutor.send(
                path: path,
                method: method,
            )
            let envelope = try apiClient.decode(APIResponseEnvelope<EmptyPayload>.self, from: data)
            guard envelope.success else {
                throw CourseReviewsClientError.unexpected
            }
        } catch let error as APIClientError {
            throw map(apiError: error)
        } catch let error as CourseReviewsClientError {
            throw error
        } catch {
            throw CourseReviewsClientError.unexpected
        }
    }

    private func map(apiError: APIClientError) -> CourseReviewsClientError {
        switch apiError {
        case .transport:
            return .network
        case let .server(statusCode, payload):
            if statusCode == 401 {
                return .invalidSession
            }

            switch payload?.code {
            case "COURSE_002":
                return .reviewNotFound
            case "COURSE_003":
                return .reviewAlreadyExists
            case "COURSE_004":
                return .targetNotFound
            default:
                return .unexpected
            }
        default:
            return .unexpected
        }
    }
}

private extension CourseReviewsAPIClient {
    struct ReviewIdResponse: Decodable {
        let reviewId: Int64
    }

    struct FeedPageResponse: Decodable {
        let items: [FeedItemResponse]
        let page: Int
        let size: Int
        let totalElements: Int
        let totalPages: Int
        let hasNext: Bool

        func toDomain() -> CourseReviewFeedPage {
            CourseReviewFeedPage(
                items: items.map(\.toDomain),
                page: page,
                size: size,
                totalElements: totalElements,
                totalPages: totalPages,
                hasNext: hasNext
            )
        }
    }

    struct FeedItemResponse: Decodable {
        let reviewId: Int64
        let targetId: Int64
        let courseId: Int64
        let courseCode: String
        let courseName: String
        let professorDisplayName: String
        let displayName: String
        let overallRating: Int
        let professorRating: Int?
        let difficulty: Int
        let workload: Int
        let wouldTakeAgain: Bool
        let content: String
        let professorContent: String?
        let academicYear: Int
        let term: String
        let isMine: Bool
        let createdAt: String
        let updatedAt: String

        var toDomain: CourseReviewFeedItem {
            CourseReviewFeedItem(
                reviewId: reviewId,
                target: CourseReviewTargetRef(
                    targetId: targetId,
                    courseId: courseId,
                    courseCode: courseCode,
                    courseName: courseName,
                    professorDisplayName: professorDisplayName,
                    displayName: displayName
                ),
                overallRating: overallRating,
                professorRating: professorRating,
                difficulty: difficulty,
                workload: workload,
                wouldTakeAgain: wouldTakeAgain,
                content: content,
                professorContent: professorContent,
                academicYear: academicYear,
                term: term,
                isMine: isMine,
                createdAt: createdAt,
                updatedAt: updatedAt
            )
        }
    }

    struct TargetPageResponse: Decodable {
        let items: [TargetItemResponse]
        let page: Int
        let size: Int
        let totalElements: Int
        let totalPages: Int
        let hasNext: Bool

        func toDomain() -> CourseReviewTargetPage {
            CourseReviewTargetPage(
                items: items.map(\.toDomain),
                page: page,
                size: size,
                totalElements: totalElements,
                totalPages: totalPages,
                hasNext: hasNext
            )
        }
    }

    struct TargetItemResponse: Decodable {
        let targetId: Int64
        let courseId: Int64
        let courseCode: String
        let courseName: String
        let professorDisplayName: String
        let displayName: String

        var toDomain: CourseReviewTargetRef {
            CourseReviewTargetRef(
                targetId: targetId,
                courseId: courseId,
                courseCode: courseCode,
                courseName: courseName,
                professorDisplayName: professorDisplayName,
                displayName: displayName
            )
        }
    }

    struct ReviewPageResponse: Decodable {
        let summary: SummaryResponse
        let reviews: [ReviewItemResponse]
        let page: Int
        let size: Int
        let totalElements: Int
        let totalPages: Int
        let hasNext: Bool

        func toDomain() -> CourseReviewPage {
            CourseReviewPage(
                summary: summary.toDomain,
                reviews: reviews.map(\.toDomain),
                page: page,
                size: size,
                totalElements: totalElements,
                totalPages: totalPages,
                hasNext: hasNext
            )
        }
    }

    struct SummaryResponse: Decodable {
        let targetId: Int64
        let courseId: Int64
        let courseCode: String
        let courseName: String
        let professorDisplayName: String
        let displayName: String
        let reviewCount: Int
        let averageOverall: Double?
        let averageProfessor: Double?
        let averageDifficulty: Double?
        let averageWorkload: Double?
        let wouldTakeAgainRate: Double?

        var toDomain: CourseReviewSummary {
            CourseReviewSummary(
                target: CourseReviewTargetRef(
                    targetId: targetId,
                    courseId: courseId,
                    courseCode: courseCode,
                    courseName: courseName,
                    professorDisplayName: professorDisplayName,
                    displayName: displayName
                ),
                reviewCount: reviewCount,
                averageOverall: averageOverall,
                averageProfessor: averageProfessor,
                averageDifficulty: averageDifficulty,
                averageWorkload: averageWorkload,
                wouldTakeAgainRate: wouldTakeAgainRate
            )
        }
    }

    struct ReviewItemResponse: Decodable {
        let reviewId: Int64
        let overallRating: Int
        let professorRating: Int?
        let difficulty: Int
        let workload: Int
        let wouldTakeAgain: Bool
        let content: String
        let professorContent: String?
        let academicYear: Int
        let term: String
        let professorDisplayName: String
        let isMine: Bool
        let createdAt: String
        let updatedAt: String

        var toDomain: CourseReviewEntry {
            CourseReviewEntry(
                reviewId: reviewId,
                overallRating: overallRating,
                professorRating: professorRating,
                difficulty: difficulty,
                workload: workload,
                wouldTakeAgain: wouldTakeAgain,
                content: content,
                professorContent: professorContent,
                academicYear: academicYear,
                term: term,
                professorDisplayName: professorDisplayName,
                isMine: isMine,
                createdAt: createdAt,
                updatedAt: updatedAt
            )
        }
    }
}

// MARK: - View Models

@MainActor
final class CourseReviewsFeedViewModel: ObservableObject {
    @Published private(set) var isLoading = false
    @Published private(set) var items: [CourseReviewFeedItem] = []
    @Published private(set) var failure: CourseReviewsFailure?
    @Published var selectedFilter: CourseReviewFeedFilter = .all
    @Published var showingAll = false

    private let client: CourseReviewsClientProtocol
    private var hasLoaded = false

    init(client: CourseReviewsClientProtocol) {
        self.client = client
    }

    func loadIfNeeded() async {
        guard hasLoaded == false else { return }
        hasLoaded = true
        await load()
    }

    func reload() async {
        await client.invalidateCache()
        await load()
    }

    func invalidateStateIfNeeded() -> Bool {
        failure == .invalidSession
    }

    var visibleItems: [CourseReviewFeedItem] {
        let filtered = items.filter { item in
            switch selectedFilter {
            case .all:
                return true
            case .liberalArts:
                return item.academicCategory == .liberalArts
            case .major:
                return item.academicCategory == .major
            case .highRating:
                return item.overallRating >= 8
            }
        }

        if showingAll {
            return filtered
        }
        return Array(filtered.prefix(4))
    }

    var canViewAll: Bool {
        items.count > 4
    }

    private func load() async {
        isLoading = true
        failure = nil

        do {
            let page = try await client.fetchReviewFeed(page: 0, size: 20)
            items = page.items
        } catch let error as CourseReviewsClientError {
            failure = Self.map(error)
        } catch {
            failure = .unexpected
        }

        isLoading = false
    }

    private static func map(_ error: CourseReviewsClientError) -> CourseReviewsFailure {
        switch error {
        case .invalidSession: return .invalidSession
        case .reviewAlreadyExists: return .reviewAlreadyExists
        case .reviewNotFound: return .reviewNotFound
        case .targetNotFound: return .targetNotFound
        case .network: return .network
        case .unexpected: return .unexpected
        }
    }
}

@MainActor
final class CourseReviewTargetSearchViewModel: ObservableObject {
    @Published private(set) var isLoading = false
    @Published private(set) var results: [CourseReviewTargetRef] = []
    @Published private(set) var failure: CourseReviewsFailure?

    private let client: CourseReviewsClientProtocol
    private var queryCache: [String: SearchCacheEntry] = [:]
    private let searchCacheMaxAge: TimeInterval = 15

    init(client: CourseReviewsClientProtocol) {
        self.client = client
    }

    func search(query: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            results = []
            failure = nil
            return
        }

        let cacheKey = trimmed.lowercased()
        if let cached = queryCache[cacheKey],
           Date().timeIntervalSince(cached.storedAt) <= searchCacheMaxAge {
            results = cached.results
            failure = nil
            return
        }

        isLoading = true
        failure = nil
        defer { isLoading = false }

        do {
            let page = try await client.fetchReviewTargets(query: query, page: 0, size: 20)
            results = page.items
            queryCache[cacheKey] = SearchCacheEntry(results: page.items, storedAt: Date())
        } catch is CancellationError {
            return
        } catch let error as CourseReviewsClientError {
            failure = Self.map(error)
        } catch {
            failure = .unexpected
        }
    }

    func resetFailure() {
        failure = nil
    }

    private static func map(_ error: CourseReviewsClientError) -> CourseReviewsFailure {
        switch error {
        case .invalidSession: return .invalidSession
        case .reviewAlreadyExists: return .reviewAlreadyExists
        case .reviewNotFound: return .reviewNotFound
        case .targetNotFound: return .targetNotFound
        case .network: return .network
        case .unexpected: return .unexpected
        }
    }

    private struct SearchCacheEntry {
        let results: [CourseReviewTargetRef]
        let storedAt: Date
    }
}

@MainActor
final class CourseReviewDetailViewModel: ObservableObject {
    @Published private(set) var isLoading = false
    @Published private(set) var page: CourseReviewPage?
    @Published private(set) var myReview: CourseReviewEntry?
    @Published private(set) var failure: CourseReviewsFailure?

    private let client: CourseReviewsClientProtocol
    private let target: CourseReviewTargetRef
    private var hasLoaded = false

    init(client: CourseReviewsClientProtocol, target: CourseReviewTargetRef) {
        self.client = client
        self.target = target
    }

    func loadIfNeeded() async {
        guard hasLoaded == false else { return }
        hasLoaded = true
        await load()
    }

    func reload() async {
        await client.invalidateCache()
        await load()
    }

    func invalidateStateIfNeeded() -> Bool {
        failure == .invalidSession
    }

    private func load() async {
        isLoading = true
        failure = nil

        do {
            let page = try await client.fetchTargetReviews(targetId: target.targetId, page: 0, size: 20)
            let myReview = try await fetchMyReviewOrNil()
            self.page = page
            self.myReview = myReview
        } catch let error as CourseReviewsClientError {
            failure = Self.map(error)
        } catch {
            failure = .unexpected
        }

        isLoading = false
    }

    private func fetchMyReviewOrNil() async throws -> CourseReviewEntry? {
        do {
            return try await client.fetchMyReview(targetId: target.targetId)
        } catch let error as CourseReviewsClientError {
            switch error {
            case .invalidSession:
                throw error
            case .reviewNotFound, .network, .unexpected, .targetNotFound, .reviewAlreadyExists:
                return nil
            }
        }
    }

    private static func map(_ error: CourseReviewsClientError) -> CourseReviewsFailure {
        switch error {
        case .invalidSession: return .invalidSession
        case .reviewAlreadyExists: return .reviewAlreadyExists
        case .reviewNotFound: return .reviewNotFound
        case .targetNotFound: return .targetNotFound
        case .network: return .network
        case .unexpected: return .unexpected
        }
    }
}

@MainActor
final class WriteReviewViewModel: ObservableObject {
    @Published var overallRating: Int = 0
    @Published var professorRating: Int = 0
    @Published var difficultySelection: Int = 3
    @Published var workloadSelection: Int = 3
    @Published var wouldTakeAgain = false
    @Published var content = ""
    @Published var professorContent = ""
    @Published var academicYear = Calendar.current.component(.year, from: Date())
    @Published var term: ReviewTerm = .spring
    @Published private(set) var existingReview: CourseReviewEntry?
    @Published private(set) var isLoading = false
    @Published private(set) var isSubmitting = false
    @Published private(set) var failure: CourseReviewsFailure?
    @Published private(set) var bannerMessage: String?

    private let client: CourseReviewsClientProtocol
    private let target: CourseReviewTargetRef
    private var hasLoaded = false

    init(client: CourseReviewsClientProtocol, target: CourseReviewTargetRef) {
        self.client = client
        self.target = target
    }

    var isEditing: Bool {
        existingReview != nil
    }

    var characterCountText: String {
        "\(content.count) / 1000"
    }

    var professorCharacterCountText: String {
        "\(professorContent.count) / 1000"
    }

    var submitTitle: String {
        isEditing ? "Update Review" : "Submit Review"
    }

    var isSubmitDisabled: Bool {
        overallRating == 0 ||
            professorRating == 0 ||
            content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func loadIfNeeded() async {
        guard hasLoaded == false else { return }
        hasLoaded = true
        await loadExistingReview()
    }

    func invalidateStateIfNeeded() -> Bool {
        failure == .invalidSession
    }

    func submit() async -> Bool {
        guard isSubmitDisabled == false else { return false }

        isSubmitting = true
        failure = nil
        bannerMessage = nil

        let request = CourseReviewUpsertRequest(
            academicYear: academicYear,
            term: term.rawValue,
            overallRating: overallRating,
            professorRating: professorRating,
            difficulty: difficultySelection,
            workload: workloadSelection,
            wouldTakeAgain: wouldTakeAgain,
            content: trimmedContent,
            professorContent: trimmedProfessorContent
        )

        do {
            if isEditing {
                _ = try await client.updateMyReview(targetId: target.targetId, request: request)
                bannerMessage = "Your review was updated."
            } else {
                _ = try await client.createReview(targetId: target.targetId, request: request)
                bannerMessage = "Your review was submitted."
            }
            await loadExistingReview()
            isSubmitting = false
            return true
        } catch let error as CourseReviewsClientError {
            failure = Self.map(error)
        } catch {
            failure = .unexpected
        }

        isSubmitting = false
        return false
    }

    func deleteReview() async -> Bool {
        guard isEditing else { return false }
        isSubmitting = true
        failure = nil

        do {
            try await client.deleteMyReview(targetId: target.targetId)
            existingReview = nil
            resetForm()
            bannerMessage = "Your review was deleted."
            isSubmitting = false
            return true
        } catch let error as CourseReviewsClientError {
            failure = Self.map(error)
        } catch {
            failure = .unexpected
        }

        isSubmitting = false
        return false
    }

    func dismissBanner() {
        bannerMessage = nil
    }

    func clearFailure() {
        failure = nil
    }

    private func loadExistingReview() async {
        isLoading = true
        failure = nil

        do {
            let review = try await client.fetchMyReview(targetId: target.targetId)
            existingReview = review
            apply(review: review)
        } catch let error as CourseReviewsClientError where error == .reviewNotFound {
            existingReview = nil
            resetForm()
        } catch let error as CourseReviewsClientError {
            failure = Self.map(error)
        } catch {
            failure = .unexpected
        }

        isLoading = false
    }

    private func apply(review: CourseReviewEntry) {
        overallRating = review.overallRating
        professorRating = review.professorRating ?? 0
        difficultySelection = review.difficulty
        workloadSelection = review.workload
        wouldTakeAgain = review.wouldTakeAgain
        content = review.content
        professorContent = review.professorContent ?? ""
        academicYear = review.academicYear
        term = ReviewTerm(rawValue: review.term.uppercased()) ?? .spring
    }

    private func resetForm() {
        overallRating = 0
        professorRating = 0
        difficultySelection = 3
        workloadSelection = 3
        wouldTakeAgain = false
        content = ""
        professorContent = ""
        academicYear = Calendar.current.component(.year, from: Date())
        term = .spring
    }

    private var trimmedContent: String {
        content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedProfessorContent: String? {
        let trimmed = professorContent.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func map(_ error: CourseReviewsClientError) -> CourseReviewsFailure {
        switch error {
        case .invalidSession: return .invalidSession
        case .reviewAlreadyExists: return .reviewAlreadyExists
        case .reviewNotFound: return .reviewNotFound
        case .targetNotFound: return .targetNotFound
        case .network: return .network
        case .unexpected: return .unexpected
        }
    }
}

// MARK: - Root Navigation

private enum CourseReviewsRoute: Hashable {
    case search(CourseReviewSearchPurpose)
    case detail(CourseReviewTargetRef, UUID)
    case write(CourseReviewTargetRef)
}

private enum CourseReviewSearchPurpose: Hashable {
    case browseDetails
    case writeReview
}

struct CourseReviewsRootView: View {
    @ObservedObject private var session: AppSession
    @StateObject private var feedViewModel: CourseReviewsFeedViewModel
    @Binding private var isTabBarHidden: Bool
    private let client: CourseReviewsClientProtocol
    private let isActive: Bool

    @State private var path: [CourseReviewsRoute] = []

    init(
        session: AppSession,
        client: CourseReviewsClientProtocol,
        isTabBarHidden: Binding<Bool> = .constant(false),
        isActive: Bool = true
    ) {
        self.session = session
        self.client = client
        self._isTabBarHidden = isTabBarHidden
        self.isActive = isActive
        _feedViewModel = StateObject(wrappedValue: CourseReviewsFeedViewModel(client: client))
    }

    var body: some View {
        NavigationStack(path: $path) {
            CourseReviewsFeedScreen(
                viewModel: feedViewModel,
                onSearchTap: {
                    path.append(.search(.browseDetails))
                },
                onOpenReview: { target in
                    path.append(.detail(target, UUID()))
                },
                onWriteTap: {
                    path.append(.search(.writeReview))
                }
            )
            .navigationDestination(for: CourseReviewsRoute.self) { route in
                switch route {
                case let .search(purpose):
                    ReviewTargetSearchScreen(
                        session: session,
                        client: client,
                        purpose: purpose,
                        onSelectTarget: { target in
                            switch purpose {
                            case .browseDetails:
                                path.append(.detail(target, UUID()))
                            case .writeReview:
                                path.append(.write(target))
                            }
                        }
                    )
                case let .detail(target, _):
                    CourseReviewDetailScreen(
                        session: session,
                        client: client,
                        target: target,
                        onWriteTap: { selectedTarget in
                            path.append(.write(selectedTarget))
                        }
                    )
                case let .write(target):
                    WriteReviewScreen(
                        session: session,
                        client: client,
                        target: target,
                        onCompleted: { completedTarget in
                            Task {
                                await feedViewModel.reload()
                            }
                            path = [.detail(completedTarget, UUID())]
                        }
                    )
                }
            }
        }
        .task(id: isActive) {
            guard isActive else { return }
            await feedViewModel.loadIfNeeded()
        }
        .onAppear {
            isTabBarHidden = path.isEmpty == false
        }
        .onChange(of: path) { _, newValue in
            isTabBarHidden = newValue.isEmpty == false
        }
        .onChange(of: isActive) { _, newValue in
            if newValue == false {
                isTabBarHidden = false
            }
        }
        .onDisappear {
            isTabBarHidden = false
        }
        .onChange(of: feedViewModel.invalidateStateIfNeeded()) { _, shouldInvalidate in
            guard shouldInvalidate else { return }
            session.invalidateSession()
        }
    }
}

typealias CourseReviewsView = CourseReviewsRootView

// MARK: - Feed Screen

private struct CourseReviewsFeedScreen: View {
    @ObservedObject var viewModel: CourseReviewsFeedViewModel
    let onSearchTap: () -> Void
    let onOpenReview: (CourseReviewTargetRef) -> Void
    let onWriteTap: () -> Void

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    searchBar
                    filterRow
                    recentSection
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, AuthenticatedLayoutMetrics.rootContentBottomSpacing)
            }
            .background(background)

            writeButton
                .padding(.trailing, 20)
                .padding(.bottom, AuthenticatedLayoutMetrics.floatingActionBottomSpacing)
        }
    }

    private var background: some View {
        AppTheme.pageBackground.ignoresSafeArea()
    }

    private var header: some View {
        HStack {
            Text("Course Evaluation")
                .font(AppFont.extraBold(30, relativeTo: .largeTitle))
                .foregroundStyle(AppTheme.textPrimary)

            Spacer()

            Button {} label: {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "bell.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(AppTheme.textSecondary)

                    Circle()
                        .fill(Color.red)
                        .frame(width: 7, height: 7)
                        .offset(x: 2, y: -2)
                }
                .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .accessibilityHidden(true)
        }
    }

    private var searchBar: some View {
        Button(action: onSearchTap) {
            HStack(spacing: 14) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(AppTheme.textSecondary)

                Text("Search by course name, professor...")
                    .font(AppFont.medium(16, relativeTo: .body))
                    .foregroundStyle(AppTheme.textSecondary)

                Spacer()
            }
            .padding(.horizontal, 20)
            .frame(height: 58)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(AppTheme.surfacePrimary)
                    .overlay {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(AppTheme.divider, lineWidth: 1)
                    }
            )
        }
        .buttonStyle(.plain)
    }

    private var filterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(CourseReviewFeedFilter.allCases, id: \.self) { filter in
                    Button {
                        viewModel.selectedFilter = filter
                    } label: {
                        HStack(spacing: 8) {
                            if filter == .all {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 12, weight: .bold))
                            }

                            Text(filter.title)
                                .font(AppFont.semibold(14, relativeTo: .subheadline))
                        }
                        .foregroundStyle(viewModel.selectedFilter == filter ? .white : AppTheme.textSecondary)
                        .padding(.horizontal, 18)
                        .frame(height: 40)
                        .background(
                            Capsule(style: .continuous)
                                .fill(viewModel.selectedFilter == filter ? AnyShapeStyle(
                                    LinearGradient(
                                        colors: [AuthPalette.primaryStart, AuthPalette.primaryEnd],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                ) : AnyShapeStyle(AppTheme.surfaceSecondary))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Recent Reviews")
                    .font(AppFont.extraBold(26, relativeTo: .title2))
                    .foregroundStyle(AppTheme.textPrimary)

                Spacer()

                if viewModel.canViewAll {
                    Button(viewModel.showingAll ? "Collapse" : "View All") {
                        viewModel.showingAll.toggle()
                    }
                    .font(AppFont.semibold(15, relativeTo: .subheadline))
                    .foregroundStyle(AuthPalette.primaryStart)
                    .buttonStyle(.plain)
                }
            }

            if let failure = viewModel.failure {
                ReviewsFailureCard(message: failure.message) {
                    Task { await viewModel.reload() }
                }
            } else if viewModel.isLoading {
                VStack(spacing: 14) {
                    ForEach(0..<3, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .fill(AppTheme.surfacePrimary)
                            .frame(height: 236)
                            .shadow(color: Color.black.opacity(0.05), radius: 18, y: 10)
                            .redacted(reason: .placeholder)
                    }
                }
            } else if viewModel.visibleItems.isEmpty {
                ReviewsEmptyCard(
                    title: "No reviews yet",
                    message: "Write the first review for a course in your university."
                )
            } else {
                VStack(spacing: 18) {
                    ForEach(viewModel.visibleItems) { item in
                        Button {
                            onOpenReview(item.target)
                        } label: {
                            CourseReviewFeedCard(item: item)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var writeButton: some View {
        Button(action: onWriteTap) {
            HStack(spacing: 10) {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 18, weight: .bold))

                Text("Write Review")
                    .font(AppFont.bold(17, relativeTo: .headline))
            }
            .foregroundStyle(Color.white)
            .padding(.horizontal, 26)
            .frame(height: 58)
            .background(
                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [AuthPalette.primaryStart, AuthPalette.primaryEnd],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            )
            .shadow(color: AuthPalette.primaryShadow, radius: 18, y: 10)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Search Screen

private struct ReviewTargetSearchScreen: View {
    @ObservedObject private var session: AppSession
    @StateObject private var viewModel: CourseReviewTargetSearchViewModel
    @State private var query = ""
    let purpose: CourseReviewSearchPurpose
    let onSelectTarget: (CourseReviewTargetRef) -> Void

    init(
        session: AppSession,
        client: CourseReviewsClientProtocol,
        purpose: CourseReviewSearchPurpose,
        onSelectTarget: @escaping (CourseReviewTargetRef) -> Void
    ) {
        self.session = session
        self.purpose = purpose
        self.onSelectTarget = onSelectTarget
        _viewModel = StateObject(wrappedValue: CourseReviewTargetSearchViewModel(client: client))
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                searchField

                if let failure = viewModel.failure {
                    ReviewsFailureCard(message: failure.message) {
                        Task { await viewModel.search(query: query) }
                    }
                } else if viewModel.isLoading {
                    ProgressView("Searching courses...")
                        .font(AppFont.medium(15, relativeTo: .subheadline))
                        .tint(AuthPalette.primaryStart)
                } else if viewModel.results.isEmpty {
                    ReviewsEmptyCard(
                        title: query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Search for a course" : "No matching courses",
                        message: query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? purpose.emptyStateMessage
                            : "Try another course code, title, or professor name."
                    )
                } else {
                    VStack(spacing: 14) {
                        ForEach(viewModel.results) { target in
                            Button {
                                onSelectTarget(target)
                            } label: {
                                ReviewTargetCard(target: target)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, AuthenticatedLayoutMetrics.pushedContentBottomSpacing)
        }
        .background(AppTheme.pageBackground.ignoresSafeArea())
        .navigationTitle(purpose.navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: query) {
            try? await Task.sleep(for: .milliseconds(250))
            guard Task.isCancelled == false else { return }
            viewModel.resetFailure()
            await viewModel.search(query: query)
        }
        .onChange(of: viewModel.failure) { _, failure in
            guard failure == .invalidSession else { return }
            session.invalidateSession()
        }
    }

    private var searchField: some View {
        HStack(spacing: 14) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(AppTheme.textTertiary)

            TextField("Search by course or professor...", text: $query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(AppFont.medium(15, relativeTo: .body))
                .foregroundStyle(AppTheme.textPrimary)
        }
        .padding(.horizontal, 18)
        .frame(height: 58)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(AppTheme.surfaceSecondary)
        )
    }
}

private extension CourseReviewSearchPurpose {
    var navigationTitle: String {
        switch self {
        case .browseDetails:
            return "Find Course"
        case .writeReview:
            return "Select Course"
        }
    }

    var emptyStateMessage: String {
        switch self {
        case .browseDetails:
            return "Type a course name or professor to explore course reviews."
        case .writeReview:
            return "Type a course name or professor to start writing a review."
        }
    }
}

// MARK: - Detail Screen

private struct CourseReviewDetailScreen: View {
    @ObservedObject private var session: AppSession
    @StateObject private var viewModel: CourseReviewDetailViewModel
    let target: CourseReviewTargetRef
    let onWriteTap: (CourseReviewTargetRef) -> Void

    init(
        session: AppSession,
        client: CourseReviewsClientProtocol,
        target: CourseReviewTargetRef,
        onWriteTap: @escaping (CourseReviewTargetRef) -> Void
    ) {
        self.session = session
        self.target = target
        self.onWriteTap = onWriteTap
        _viewModel = StateObject(wrappedValue: CourseReviewDetailViewModel(client: client, target: target))
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                if let failure = viewModel.failure {
                    ReviewsFailureCard(message: failure.message) {
                        Task { await viewModel.reload() }
                    }
                } else if viewModel.isLoading, viewModel.page == nil {
                    ProgressView("Loading reviews...")
                        .font(AppFont.medium(15, relativeTo: .subheadline))
                        .tint(AuthPalette.primaryStart)
                } else if let page = viewModel.page {
                    ReviewSummaryCard(summary: page.summary)

                    HStack {
                        Text("Reviews")
                            .font(AppFont.extraBold(24, relativeTo: .title2))
                            .foregroundStyle(AppTheme.textPrimary)

                        Spacer()

                        Button(viewModel.myReview == nil ? "Write Review" : "Edit My Review") {
                            onWriteTap(page.summary.target)
                        }
                        .font(AppFont.semibold(14, relativeTo: .subheadline))
                        .foregroundStyle(AuthPalette.primaryStart)
                        .buttonStyle(.plain)
                    }

                    if page.reviews.isEmpty {
                        ReviewsEmptyCard(
                            title: "No reviews yet",
                            message: "Be the first to review this course."
                        )
                    } else {
                        VStack(spacing: 16) {
                            ForEach(page.reviews) { review in
                                ReviewDetailCard(review: review)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, AuthenticatedLayoutMetrics.pushedContentBottomSpacing)
        }
        .background(AppTheme.pageBackground.ignoresSafeArea())
        .navigationTitle(target.courseName)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.loadIfNeeded()
        }
        .onChange(of: viewModel.invalidateStateIfNeeded()) { _, shouldInvalidate in
            guard shouldInvalidate else { return }
            session.invalidateSession()
        }
    }
}

// MARK: - Write Screen

private struct WriteReviewScreen: View {
    @ObservedObject private var session: AppSession
    @StateObject private var viewModel: WriteReviewViewModel
    let target: CourseReviewTargetRef
    let onCompleted: (CourseReviewTargetRef) -> Void

    init(
        session: AppSession,
        client: CourseReviewsClientProtocol,
        target: CourseReviewTargetRef,
        onCompleted: @escaping (CourseReviewTargetRef) -> Void
    ) {
        self.session = session
        self.target = target
        self.onCompleted = onCompleted
        _viewModel = StateObject(wrappedValue: WriteReviewViewModel(client: client, target: target))
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 28) {
                targetCard
                termSection
                ratingSection
                characteristicsSection
                feedbackSection
                guidelinesSection
            }
            .padding(.horizontal, 24)
            .padding(.top, 18)
            .padding(.bottom, AuthenticatedLayoutMetrics.accessoryContentBottomSpacing)
        }
        .background(AppTheme.pageBackground.ignoresSafeArea())
        .navigationTitle(viewModel.isEditing ? "Edit Review" : "Write Review")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if viewModel.isEditing {
                    Menu {
                        Button(role: .destructive) {
                            Task {
                                let deleted = await viewModel.deleteReview()
                                if deleted {
                                    onCompleted(target)
                                }
                            }
                        } label: {
                            Label("Delete Review", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(AppTheme.textPrimary)
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 10) {
                if let message = viewModel.bannerMessage {
                    ReviewsInlineBanner(message: message) {
                        viewModel.dismissBanner()
                    }
                    .padding(.horizontal, 20)
                }

                PrimaryActionButton(
                    title: viewModel.submitTitle,
                    isLoading: viewModel.isSubmitting,
                    isDisabled: viewModel.isSubmitDisabled,
                    height: 64,
                    cornerRadius: 20
                ) {
                    Task {
                        let succeeded = await viewModel.submit()
                        if succeeded {
                            onCompleted(target)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 8)
                .background(
                    AppTheme.backgroundTop.opacity(0.96)
                        .ignoresSafeArea(edges: .bottom)
                )
            }
        }
        .task {
            await viewModel.loadIfNeeded()
        }
        .onChange(of: viewModel.invalidateStateIfNeeded()) { _, shouldInvalidate in
            guard shouldInvalidate else { return }
            session.invalidateSession()
        }
        .alert(
            "Unable to submit review",
            isPresented: Binding(
                get: { viewModel.failure != nil },
                set: { newValue in
                    if newValue == false {
                        viewModel.clearFailure()
                    }
                }
            ),
            actions: {
                Button("OK") {
                    viewModel.clearFailure()
                }
            },
            message: {
                Text(viewModel.failure?.message ?? "")
            }
        )
    }

    private var targetCard: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(AuthPalette.primaryStart.opacity(0.16))

            VStack(alignment: .leading, spacing: 14) {
                Text("TARGET COURSE")
                    .font(AppFont.bold(13, relativeTo: .caption))
                    .tracking(2)
                    .foregroundStyle(AuthPalette.primaryStart)

                Text(target.courseName)
                    .font(AppFont.extraBold(24, relativeTo: .title))
                    .foregroundStyle(AppTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    Image(systemName: "person.fill")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(AppTheme.textSecondary)

                    Text(target.professorDisplayName)
                        .font(AppFont.medium(15, relativeTo: .body))
                        .foregroundStyle(AppTheme.textSecondary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 22)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(AppTheme.surfacePrimary)
                    .shadow(color: Color.black.opacity(0.05), radius: 18, y: 10)
            )
            .padding(.leading, 4)
            .padding(.trailing, 2)
            .padding(.vertical, 4)
        }
    }

    private var termSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("WHEN DID YOU TAKE IT?")
                .font(AppFont.bold(13, relativeTo: .caption))
                .tracking(2)
                .foregroundStyle(AppTheme.textSecondary)

            HStack(spacing: 12) {
                Menu {
                    ForEach(Array((2020...Calendar.current.component(.year, from: Date()) + 1).reversed()), id: \.self) { year in
                        Button(String(year)) {
                            viewModel.academicYear = year
                        }
                    }
                } label: {
                    ReviewFormPill(title: String(viewModel.academicYear))
                }

                ForEach(ReviewTerm.allCases) { term in
                    Button {
                        viewModel.term = term
                    } label: {
                        Text(term.title)
                            .font(AppFont.semibold(15, relativeTo: .body))
                            .foregroundStyle(viewModel.term == term ? .white : AppTheme.textSecondary)
                            .padding(.horizontal, 18)
                            .frame(height: 42)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(viewModel.term == term ? AnyShapeStyle(
                                        LinearGradient(
                                            colors: [AuthPalette.primaryStart, AuthPalette.primaryEnd],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    ) : AnyShapeStyle(AppTheme.surfaceSecondary))
                    )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var ratingSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("RATINGS")
                .font(AppFont.bold(13, relativeTo: .caption))
                .tracking(2)
                .foregroundStyle(AppTheme.textSecondary)

            VStack(spacing: 18) {
                ReviewStarRatingPicker(
                    title: "Class",
                    value: viewModel.overallRating,
                    onSelect: { viewModel.overallRating = $0 }
                )

                ReviewStarRatingPicker(
                    title: "Professor",
                    value: viewModel.professorRating,
                    onSelect: { viewModel.professorRating = $0 }
                )
            }
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(AppTheme.surfaceSecondary)
            )
        }
    }

    private var characteristicsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("COURSE CHARACTERISTICS")
                .font(AppFont.bold(13, relativeTo: .caption))
                .tracking(2)
                .foregroundStyle(AppTheme.textSecondary)

            ReviewChipRow(
                title: "Difficulty",
                options: [
                    ReviewChipOption(title: "Easy", value: 1),
                    ReviewChipOption(title: "Balanced", value: 3),
                    ReviewChipOption(title: "Challenging", value: 5)
                ],
                selectedValue: viewModel.difficultySelection,
                onSelect: { viewModel.difficultySelection = $0 }
            )

            ReviewChipRow(
                title: "Workload",
                options: [
                    ReviewChipOption(title: "Light Load", value: 1),
                    ReviewChipOption(title: "Normal", value: 3),
                    ReviewChipOption(title: "Heavy Load", value: 5)
                ],
                selectedValue: viewModel.workloadSelection,
                onSelect: { viewModel.workloadSelection = $0 }
            )

            Button {
                viewModel.wouldTakeAgain.toggle()
            } label: {
                Text("Would Take Again")
                    .font(AppFont.semibold(15, relativeTo: .body))
                    .foregroundStyle(viewModel.wouldTakeAgain ? .white : AppTheme.textSecondary)
                    .padding(.horizontal, 20)
                    .frame(height: 40)
                    .background(
                        Capsule(style: .continuous)
                            .fill(viewModel.wouldTakeAgain ? AnyShapeStyle(
                                LinearGradient(
                                    colors: [AuthPalette.primaryStart, AuthPalette.primaryEnd],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            ) : AnyShapeStyle(AppTheme.surfaceSecondary))
                    )
            }
            .buttonStyle(.plain)
        }
    }

    private var feedbackSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("FEEDBACK")
                .font(AppFont.bold(13, relativeTo: .caption))
                .tracking(2)
                .foregroundStyle(AppTheme.textSecondary)

            ReviewTextEditorBox(
                title: "Class Review",
                text: $viewModel.content,
                placeholder: "Write your class review here...",
                countText: viewModel.characterCountText
            )

            ReviewTextEditorBox(
                title: "Professor Review",
                text: $viewModel.professorContent,
                placeholder: "Write your professor review here...",
                countText: viewModel.professorCharacterCountText
            )
        }
    }

    private var guidelinesSection: some View {
        HStack(alignment: .top, spacing: 16) {
            ZStack {
                Circle()
                    .fill(AppTheme.textSecondary)
                    .frame(width: 32, height: 32)

                Image(systemName: "info")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("COMMUNITY GUIDELINES")
                    .font(AppFont.bold(13, relativeTo: .caption))
                    .tracking(1.5)
                    .foregroundStyle(AppTheme.textPrimary)

                Text("Please provide honest, constructive feedback. Avoid personal attacks on faculty or other students. Reviews are moderated for quality and authenticity.")
                    .font(AppFont.medium(15, relativeTo: .body))
                    .foregroundStyle(AppTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(AppTheme.surfaceSecondary)
        )
    }
}

// MARK: - Shared Review UI

private struct CourseReviewFeedCard: View {
    let item: CourseReviewFeedItem

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(item.target.courseName)
                        .font(AppFont.extraBold(21, relativeTo: .title3))
                        .foregroundStyle(AppTheme.textPrimary)
                        .lineLimit(2)

                    HStack(spacing: 8) {
                        Image(systemName: "person.fill")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(AppTheme.textTertiary)

                        Text(item.target.professorDisplayName)
                            .font(AppFont.medium(14, relativeTo: .subheadline))
                            .foregroundStyle(AppTheme.textTertiary)
                    }
                }

                Spacer(minLength: 12)

                ReviewRatingPair(
                    classRating: item.overallRating,
                    professorRating: item.professorRating
                )
            }

            FlowLayout(item.presentationTags, spacing: 10, lineSpacing: 10) { tag in
                ReviewTagChip(tag: tag)
            }

            Text(item.content)
                .font(AppFont.medium(16, relativeTo: .body))
                .foregroundStyle(AppTheme.textPrimary)
                .lineLimit(3)

                    HStack {
                Text(verbatim: "\(item.term.titleText) \(item.academicYear)")
                    .font(AppFont.medium(13, relativeTo: .caption))
                    .foregroundStyle(AppTheme.textTertiary)

                Spacer()

                Text(verbatim: item.createdAt.relativeDisplayText)
                    .font(AppFont.medium(13, relativeTo: .caption))
                    .foregroundStyle(AppTheme.textTertiary)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(AppTheme.surfacePrimary)
                .shadow(color: Color.black.opacity(0.06), radius: 18, y: 10)
        )
    }
}

private struct ReviewTargetCard: View {
    let target: CourseReviewTargetRef

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(target.courseName)
                .font(AppFont.bold(18, relativeTo: .headline))
                .foregroundStyle(AppTheme.textPrimary)

            Text(target.professorDisplayName)
                .font(AppFont.medium(14, relativeTo: .subheadline))
                .foregroundStyle(AppTheme.textSecondary)

            Text(target.courseCode)
                .font(AppFont.semibold(12, relativeTo: .caption))
                .foregroundStyle(AuthPalette.primaryStart)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(AppTheme.surfacePrimary)
                .shadow(color: Color.black.opacity(0.05), radius: 14, y: 8)
        )
    }
}

private struct ReviewSummaryCard: View {
    let summary: CourseReviewSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(summary.target.courseName)
                .font(AppFont.extraBold(22, relativeTo: .title2))
                .foregroundStyle(AppTheme.textPrimary)

            Text(summary.target.professorDisplayName)
                .font(AppFont.medium(14, relativeTo: .headline))
                .foregroundStyle(AppTheme.textSecondary)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 2), spacing: 10) {
                SummaryStat(title: "Class", value: summary.averageOverall.flatMap { String(format: "%.1f", $0) } ?? "-")
                SummaryStat(title: "Professor", value: summary.averageProfessor.flatMap { String(format: "%.1f", $0) } ?? "-")
                SummaryStat(title: "Difficulty", value: summary.averageDifficulty.difficultySummaryText)
                SummaryStat(title: "Workload", value: summary.averageWorkload.workloadSummaryText)
            }

            HStack {
                Text(verbatim: "\(summary.reviewCount) reviews")
                    .font(AppFont.semibold(14, relativeTo: .subheadline))
                    .foregroundStyle(AppTheme.textSecondary)

                Spacer()

                Text("Would take again \(summary.wouldTakeAgainRate.flatMap { String(format: "%.0f%%", $0) } ?? "-")")
                    .font(AppFont.semibold(14, relativeTo: .subheadline))
                    .foregroundStyle(AuthPalette.primaryStart)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(AppTheme.surfacePrimary)
                .shadow(color: Color.black.opacity(0.06), radius: 18, y: 10)
        )
    }
}

private struct ReviewDetailCard: View {
    let review: CourseReviewEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(review.isMine ? "Your Review" : "Anonymous Student")
                    .font(AppFont.bold(15, relativeTo: .headline))
                    .foregroundStyle(AppTheme.textPrimary)

                Spacer()

                ReviewRatingPair(
                    classRating: review.overallRating,
                    professorRating: review.professorRating
                )
            }

            FlowLayout(review.presentationTags, spacing: 10, lineSpacing: 10) { tag in
                ReviewTagChip(tag: tag)
            }

            Text(review.content)
                .font(AppFont.medium(15, relativeTo: .body))
                .foregroundStyle(AppTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            if let professorContent = review.professorContent, professorContent.isEmpty == false {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Professor")
                        .font(AppFont.bold(11, relativeTo: .caption))
                        .tracking(1)
                        .foregroundStyle(AppTheme.textSecondary)

                    Text(professorContent)
                        .font(AppFont.medium(15, relativeTo: .body))
                        .foregroundStyle(AppTheme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(AppTheme.surfaceSecondary)
                )
            }

            HStack {
                Text(verbatim: "\(review.term.titleText) \(review.academicYear)")
                    .font(AppFont.medium(14, relativeTo: .caption))
                    .foregroundStyle(AppTheme.textTertiary)

                Spacer()

                Text(verbatim: review.createdAt.relativeDisplayText)
                    .font(AppFont.medium(14, relativeTo: .caption))
                    .foregroundStyle(AppTheme.textTertiary)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(AppTheme.surfacePrimary)
                .shadow(color: Color.black.opacity(0.05), radius: 16, y: 8)
        )
    }
}

private struct ReviewsFailureCard: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Unable to load reviews")
                .font(AppFont.bold(20, relativeTo: .title3))
                .foregroundStyle(AppTheme.textPrimary)

            Text(message)
                .font(AppFont.medium(15, relativeTo: .body))
                .foregroundStyle(AppTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            PrimaryActionButton(
                title: "Try Again",
                isLoading: false,
                isDisabled: false,
                height: 58,
                cornerRadius: 18,
                action: onRetry
            )
        }
        .padding(22)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(AppTheme.surfacePrimary)
                .shadow(color: Color.black.opacity(0.05), radius: 16, y: 8)
        )
    }
}

private struct ReviewsInlineBanner: View {
    let message: String
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.95))

            Text(message)
                .font(AppFont.semibold(14, relativeTo: .subheadline))
                .foregroundStyle(Color.white)
                .multilineTextAlignment(.leading)

            Spacer(minLength: 8)

            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.95))
                    .frame(width: 28, height: 28)
                    .background(Color.white.opacity(0.14), in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.95, green: 0.32, blue: 0.27),
                            Color(red: 0.89, green: 0.19, blue: 0.20)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
        )
        .shadow(color: Color.red.opacity(0.18), radius: 14, y: 8)
    }
}

private struct ReviewsEmptyCard: View {
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(AppFont.bold(20, relativeTo: .title3))
                .foregroundStyle(AppTheme.textPrimary)

            Text(message)
                .font(AppFont.medium(15, relativeTo: .body))
                .foregroundStyle(AppTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(AppTheme.surfacePrimary)
                .shadow(color: Color.black.opacity(0.05), radius: 16, y: 8)
        )
    }
}

private struct ReviewTextEditorBox: View {
    let title: String
    @Binding var text: String
    let placeholder: String
    let countText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(AppFont.semibold(14, relativeTo: .subheadline))
                .foregroundStyle(AppTheme.textSecondary)

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(AppTheme.surfaceSecondary)

                TextEditor(text: $text)
                    .font(AppFont.medium(16, relativeTo: .body))
                    .foregroundStyle(AppTheme.textPrimary)
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                    .accessibilityLabel(title)

                if text.isEmpty {
                    Text(placeholder)
                        .font(AppFont.medium(16, relativeTo: .body))
                        .foregroundStyle(AppTheme.textTertiary)
                        .padding(.horizontal, 20)
                        .padding(.top, 24)
                        .allowsHitTesting(false)
                }

                VStack {
                    Spacer()

                    HStack {
                        Spacer()

                        Text(countText)
                            .font(AppFont.semibold(13, relativeTo: .caption))
                            .foregroundStyle(AppTheme.textTertiary)
                            .padding(.trailing, 18)
                            .padding(.bottom, 18)
                    }
                }
            }
            .frame(height: 220)
        }
    }
}

private struct ReviewRatingPair: View {
    let classRating: Int
    let professorRating: Int?

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            ReviewRatingBadge(title: "Class", value: "\(classRating)")
            ReviewRatingBadge(title: "Prof", value: professorRating.map { String($0) } ?? "-")
        }
    }
}

private struct ReviewRatingBadge: View {
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 5) {
            Text(title)
                .font(AppFont.bold(10, relativeTo: .caption))
                .foregroundStyle(AppTheme.textSecondary)

            Text(value)
                .font(AppFont.extraBold(15, relativeTo: .headline))
                .foregroundStyle(AppTheme.textPrimary)

            Image(systemName: "star.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color(red: 0.98, green: 0.75, blue: 0.10))
        }
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(
            Capsule(style: .continuous)
                .fill(AppTheme.surfaceSecondary)
        )
    }
}

private struct SummaryStat: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(AppFont.bold(10, relativeTo: .caption))
                .tracking(0.8)
                .foregroundStyle(AppTheme.textSecondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Text(value)
                .font(AppFont.extraBold(16, relativeTo: .title3))
                .foregroundStyle(AuthPalette.primaryStart)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(AppTheme.surfaceSecondary)
        )
    }
}

private struct ReviewTagChip: View {
    let tag: ReviewPresentationTag

    var body: some View {
        Text(tag.title)
            .font(AppFont.semibold(13, relativeTo: .caption))
            .foregroundStyle(tag.foregroundColor)
            .padding(.horizontal, 14)
            .frame(height: 30)
            .background(
                Capsule(style: .continuous)
                    .fill(tag.backgroundColor)
            )
    }
}

private struct ReviewStarRatingPicker: View {
    let title: String
    let value: Int
    let onSelect: (Int) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 5)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(AppFont.semibold(14, relativeTo: .subheadline))
                    .foregroundStyle(AppTheme.textSecondary)

                Spacer()

                Text(value == 0 ? "-" : "\(value)")
                    .font(AppFont.extraBold(16, relativeTo: .headline))
                    .foregroundStyle(AuthPalette.primaryStart)
            }

            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(1...10, id: \.self) { score in
                    Button {
                        onSelect(score)
                    } label: {
                        Image(systemName: score <= value ? "star.fill" : "star")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(score <= value ? AuthPalette.primaryStart : AppTheme.textTertiary)
                            .frame(maxWidth: .infinity, minHeight: 36)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(title) rating \(score) of 10")
                    .accessibilityValue(score <= value ? "Selected" : "Not selected")
                }
            }
        }
    }
}

private struct ReviewChipOption: Identifiable, Hashable {
    let title: String
    let value: Int

    var id: Int { value }
}

private struct ReviewChipRow: View {
    let title: String
    let options: [ReviewChipOption]
    let selectedValue: Int
    let onSelect: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(AppFont.semibold(14, relativeTo: .subheadline))
                .foregroundStyle(AppTheme.textSecondary)

            FlowLayout(options, spacing: 12, lineSpacing: 12) { option in
                    Button {
                        onSelect(option.value)
                    } label: {
                        Text(option.title)
                            .font(AppFont.semibold(15, relativeTo: .body))
                            .foregroundStyle(selectedValue == option.value ? .white : AppTheme.textSecondary)
                            .padding(.horizontal, 18)
                            .frame(height: 40)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(selectedValue == option.value ? AnyShapeStyle(
                                        LinearGradient(
                                            colors: [AuthPalette.primaryStart, AuthPalette.primaryEnd],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    ) : AnyShapeStyle(AppTheme.surfaceSecondary))
                            )
                    }
                    .buttonStyle(.plain)
            }
        }
    }
}

private struct ReviewFormPill: View {
    let title: String

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(AppFont.semibold(15, relativeTo: .body))
            Image(systemName: "chevron.down")
                .font(.system(size: 12, weight: .bold))
        }
        .foregroundStyle(AppTheme.textSecondary)
        .padding(.horizontal, 18)
        .frame(height: 42)
        .background(
            Capsule(style: .continuous)
                .fill(AppTheme.surfaceSecondary)
        )
    }
}

private struct FlowLayout<Data: RandomAccessCollection, Content: View>: View where Data.Element: Hashable {
    private let data: Data
    private let spacing: CGFloat
    private let lineSpacing: CGFloat
    private let content: (Data.Element) -> Content

    init(
        _ data: Data,
        spacing: CGFloat,
        lineSpacing: CGFloat,
        @ViewBuilder content: @escaping (Data.Element) -> Content
    ) {
        self.data = data
        self.spacing = spacing
        self.lineSpacing = lineSpacing
        self.content = content
    }

    var body: some View {
        ChipFlowLayout(spacing: spacing, lineSpacing: lineSpacing) {
            ForEach(Array(data), id: \.self) { item in
                content(item)
            }
        }
    }
}

private struct ChipFlowLayout: Layout {
    let spacing: CGFloat
    let lineSpacing: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let maxWidth = proposal.width ?? 320
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + lineSpacing
                rowHeight = 0
            }

            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }

        return CGSize(width: maxWidth, height: y + rowHeight)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + lineSpacing
                rowHeight = 0
            }

            subview.place(
                at: CGPoint(x: x, y: y),
                proposal: ProposedViewSize(width: size.width, height: size.height)
            )

            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - Presentation Mapping

private struct ReviewPresentationTag: Hashable {
    let title: String
    let backgroundColor: Color
    let foregroundColor: Color
}

private enum CourseReviewAcademicCategory {
    case liberalArts
    case major
}

private extension CourseReviewFeedItem {
    var academicCategory: CourseReviewAcademicCategory {
        target.academicCategory
    }

    var presentationTags: [ReviewPresentationTag] {
        ReviewTagMapper.tags(
            difficulty: difficulty,
            workload: workload,
            wouldTakeAgain: wouldTakeAgain
        )
    }
}

private extension CourseReviewEntry {
    var presentationTags: [ReviewPresentationTag] {
        ReviewTagMapper.tags(
            difficulty: difficulty,
            workload: workload,
            wouldTakeAgain: wouldTakeAgain
        )
    }
}

private extension CourseReviewTargetRef {
    var academicCategory: CourseReviewAcademicCategory {
        let haystack = "\(courseCode) \(courseName)".lowercased()
        let liberalArtsKeywords = [
            "history",
            "psychology",
            "philosophy",
            "literature",
            "english",
            "linguistics",
            "sociology",
            "politics",
            "language",
            "art",
            "music"
        ]

        if liberalArtsKeywords.contains(where: haystack.contains) {
            return .liberalArts
        }

        return .major
    }
}

private enum ReviewTagMapper {
    static func tags(
        difficulty: Int,
        workload: Int,
        wouldTakeAgain: Bool
    ) -> [ReviewPresentationTag] {
        var result: [ReviewPresentationTag] = []

        if difficulty <= 2 {
            result.append(.init(
                title: "Easy",
                backgroundColor: Color(red: 0.91, green: 0.98, blue: 0.93),
                foregroundColor: Color(red: 0.16, green: 0.63, blue: 0.28)
            ))
        } else if difficulty >= 4 {
            result.append(.init(
                title: "Challenging",
                backgroundColor: Color(red: 1.00, green: 0.94, blue: 0.90),
                foregroundColor: Color(red: 0.88, green: 0.38, blue: 0.05)
            ))
        } else {
            result.append(.init(
                title: "Balanced",
                backgroundColor: Color(red: 0.93, green: 0.96, blue: 1.00),
                foregroundColor: Color(red: 0.17, green: 0.39, blue: 0.95)
            ))
        }

        if workload >= 4 {
            result.append(.init(
                title: "Heavy Load",
                backgroundColor: Color(red: 1.00, green: 0.93, blue: 0.94),
                foregroundColor: Color(red: 0.90, green: 0.19, blue: 0.19)
            ))
        } else if workload <= 2 {
            result.append(.init(
                title: "Light Load",
                backgroundColor: Color(red: 0.94, green: 0.97, blue: 1.00),
                foregroundColor: Color(red: 0.18, green: 0.44, blue: 0.96)
            ))
        }

        if wouldTakeAgain {
            result.append(.init(
                title: "Would Take Again",
                backgroundColor: Color(red: 0.95, green: 0.92, blue: 1.00),
                foregroundColor: Color(red: 0.47, green: 0.14, blue: 0.90)
            ))
        }

        return Array(result.prefix(3))
    }
}

private extension String {
    var titleText: String {
        capitalized
    }

    var relativeDisplayText: String {
        let date = CourseReviewDateParser.parse(self)
        guard let date else {
            return "Recently"
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

private enum CourseReviewDateParser {
    static func parse(_ source: String) -> Date? {
        let iso8601WithFractionalSeconds: ISO8601DateFormatter = {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return formatter
        }()

        let iso8601: ISO8601DateFormatter = {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime]
            return formatter
        }()

        let backendDateFormatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSX"
            return formatter
        }()

        return iso8601WithFractionalSeconds.date(from: source)
            ?? iso8601.date(from: source)
            ?? backendDateFormatter.date(from: source)
    }
}

private extension Optional where Wrapped == Double {
    var difficultySummaryText: String {
        guard let value = self else { return "-" }
        switch value {
        case ..<2.5:
            return "Easy"
        case 2.5..<3.5:
            return "Moderate"
        default:
            return "Hard"
        }
    }

    var workloadSummaryText: String {
        guard let value = self else { return "-" }
        switch value {
        case ..<2.5:
            return "Light"
        case 2.5..<3.5:
            return "Normal"
        default:
            return "Heavy"
        }
    }
}

// MARK: - Preview Support

struct PreviewCourseReviewsClient: CourseReviewsClientProtocol {
    enum Scenario {
        case loaded
        case empty
        case failing
        case writePrefilled
    }

    let scenario: Scenario

    static func loaded() -> PreviewCourseReviewsClient {
        PreviewCourseReviewsClient(scenario: .loaded)
    }

    func fetchReviewFeed(page: Int, size: Int) async throws -> CourseReviewFeedPage {
        switch scenario {
        case .empty:
            return CourseReviewFeedPage(items: [], page: 0, size: size, totalElements: 0, totalPages: 0, hasNext: false)
        case .failing:
            throw CourseReviewsClientError.network
        default:
            return PreviewCourseReviewsData.feedPage
        }
    }

    func fetchReviewTargets(query: String, page: Int, size: Int) async throws -> CourseReviewTargetPage {
        let items = PreviewCourseReviewsData.targets.filter {
            query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || $0.courseName.localizedCaseInsensitiveContains(query)
                || $0.professorDisplayName.localizedCaseInsensitiveContains(query)
                || $0.courseCode.localizedCaseInsensitiveContains(query)
        }
        return CourseReviewTargetPage(items: items, page: 0, size: size, totalElements: items.count, totalPages: 1, hasNext: false)
    }

    func fetchTargetReviews(targetId: Int64, page: Int, size: Int) async throws -> CourseReviewPage {
        PreviewCourseReviewsData.detailPage
    }

    func fetchMyReview(targetId: Int64) async throws -> CourseReviewEntry {
        switch scenario {
        case .writePrefilled:
            return PreviewCourseReviewsData.myReview
        default:
            throw CourseReviewsClientError.reviewNotFound
        }
    }

    func createReview(targetId: Int64, request: CourseReviewUpsertRequest) async throws -> Int64 {
        999
    }

    func updateMyReview(targetId: Int64, request: CourseReviewUpsertRequest) async throws -> Int64 {
        999
    }

    func deleteMyReview(targetId: Int64) async throws {}
}

enum PreviewCourseReviewsData {
    static let target = CourseReviewTargetRef(
        targetId: 11,
        courseId: 201,
        courseCode: "ECON501",
        courseName: "Advanced Microeconomics",
        professorDisplayName: "Kenichi Tanaka",
        displayName: "Advanced Microeconomics: Kenichi Tanaka"
    )

    static let targets = [
        target,
        CourseReviewTargetRef(
            targetId: 12,
            courseId: 202,
            courseCode: "HIST210",
            courseName: "Intro to Japanese History",
            professorDisplayName: "Prof. Yuko Sato",
            displayName: "Intro to Japanese History: Prof. Yuko Sato"
        ),
        CourseReviewTargetRef(
            targetId: 13,
            courseId: 203,
            courseCode: "CS102",
            courseName: "Foundations of CS",
            professorDisplayName: "Prof. Ichiro Suzuki",
            displayName: "Foundations of CS: Prof. Ichiro Suzuki"
        )
    ]

    static let feedPage = CourseReviewFeedPage(
        items: [
            CourseReviewFeedItem(
                reviewId: 101,
                target: CourseReviewTargetRef(
                    targetId: 14,
                    courseId: 204,
                    courseCode: "ECON101",
                    courseName: "Microeconomics I",
                    professorDisplayName: "Prof. Kenichi Tanaka",
                    displayName: "Microeconomics I: Prof. Kenichi Tanaka"
                ),
                overallRating: 10,
                professorRating: 9,
                difficulty: 2,
                workload: 2,
                wouldTakeAgain: true,
                content: "The professor's explanations are engaging, and you can build a solid foundation in economics. Exams are open-book and the pacing feels fair.",
                professorContent: "Prof. Tanaka makes dense concepts feel approachable and keeps office hours useful.",
                academicYear: 2023,
                term: "SPRING",
                isMine: false,
                createdAt: "2026-03-24T00:00:00.000Z",
                updatedAt: "2026-03-24T00:00:00.000Z"
            ),
            CourseReviewFeedItem(
                reviewId: 102,
                target: CourseReviewTargetRef(
                    targetId: 15,
                    courseId: 205,
                    courseCode: "HIST120",
                    courseName: "Intro to Japanese History",
                    professorDisplayName: "Prof. Yuko Sato",
                    displayName: "Intro to Japanese History: Prof. Yuko Sato"
                ),
                overallRating: 6,
                professorRating: 7,
                difficulty: 4,
                workload: 5,
                wouldTakeAgain: false,
                content: "There is a short report due every class. The content is interesting, but the workload is high and you should consider your semester balance.",
                professorContent: "Prof. Sato gives detailed context, though the pace can feel demanding.",
                academicYear: 2023,
                term: "FALL",
                isMine: false,
                createdAt: "2026-03-23T00:00:00.000Z",
                updatedAt: "2026-03-23T00:00:00.000Z"
            ),
            CourseReviewFeedItem(
                reviewId: 103,
                target: CourseReviewTargetRef(
                    targetId: 16,
                    courseId: 206,
                    courseCode: "CS100",
                    courseName: "Foundations of CS",
                    professorDisplayName: "Prof. Ichiro Suzuki",
                    displayName: "Foundations of CS: Prof. Ichiro Suzuki"
                ),
                overallRating: 8,
                professorRating: nil,
                difficulty: 3,
                workload: 2,
                wouldTakeAgain: true,
                content: "The professor teaches kindly even for those with no programming experience. TAs are also friendly, making it a good first technical course.",
                professorContent: nil,
                academicYear: 2023,
                term: "SPRING",
                isMine: false,
                createdAt: "2026-03-21T00:00:00.000Z",
                updatedAt: "2026-03-21T00:00:00.000Z"
            )
        ],
        page: 0,
        size: 20,
        totalElements: 3,
        totalPages: 1,
        hasNext: false
    )

    static let myReview = CourseReviewEntry(
        reviewId: 201,
        overallRating: 8,
        professorRating: 9,
        difficulty: 3,
        workload: 2,
        wouldTakeAgain: true,
        content: "Well structured lectures and fair grading. I would take it again.",
        professorContent: "The professor explains tradeoffs clearly and responds quickly to questions.",
        academicYear: 2025,
        term: "SPRING",
        professorDisplayName: target.professorDisplayName,
        isMine: true,
        createdAt: "2026-03-20T00:00:00.000Z",
        updatedAt: "2026-03-22T00:00:00.000Z"
    )

    static let detailPage = CourseReviewPage(
        summary: CourseReviewSummary(
            target: target,
            reviewCount: 12,
            averageOverall: 8.6,
            averageProfessor: 9.1,
            averageDifficulty: 3.2,
            averageWorkload: 2.8,
            wouldTakeAgainRate: 81.0
        ),
        reviews: [
            myReview,
            CourseReviewEntry(
                reviewId: 202,
                overallRating: 10,
                professorRating: 10,
                difficulty: 2,
                workload: 3,
                wouldTakeAgain: true,
                content: "Great for building intuition before advanced macro. The examples are practical and easy to follow.",
                professorContent: "Lectures are calm, organized, and easy to revisit before exams.",
                academicYear: 2024,
                term: "FALL",
                professorDisplayName: target.professorDisplayName,
                isMine: false,
                createdAt: "2026-03-18T00:00:00.000Z",
                updatedAt: "2026-03-18T00:00:00.000Z"
            )
        ],
        page: 0,
        size: 20,
        totalElements: 2,
        totalPages: 1,
        hasNext: false
    )
}

// MARK: - Previews

struct CourseReviewsRootView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            CourseReviewsRootView(
                session: PreviewFactory.makeSession(state: .authenticated),
                client: PreviewCourseReviewsClient.loaded()
            )
            .previewDisplayName("Reviews Feed")

            CourseReviewsRootView(
                session: PreviewFactory.makeSession(state: .authenticated),
                client: PreviewCourseReviewsClient.loaded()
            )
            .preferredColorScheme(.dark)
            .previewDisplayName("Reviews Feed - Dark")

            NavigationStack {
                WriteReviewScreen(
                    session: PreviewFactory.makeSession(state: .authenticated),
                    client: PreviewCourseReviewsClient(scenario: .writePrefilled),
                    target: PreviewCourseReviewsData.target,
                    onCompleted: { _ in }
                )
            }
            .previewDisplayName("Write Review")

            NavigationStack {
                WriteReviewScreen(
                    session: PreviewFactory.makeSession(state: .authenticated),
                    client: PreviewCourseReviewsClient(scenario: .writePrefilled),
                    target: PreviewCourseReviewsData.target,
                    onCompleted: { _ in }
                )
            }
            .preferredColorScheme(.dark)
            .previewDisplayName("Write Review - Dark")

            NavigationStack {
                CourseReviewDetailScreen(
                    session: PreviewFactory.makeSession(state: .authenticated),
                    client: PreviewCourseReviewsClient.loaded(),
                    target: PreviewCourseReviewsData.target,
                    onWriteTap: { _ in }
                )
            }
            .previewDisplayName("Review Detail")

            CourseReviewsRootView(
                session: PreviewFactory.makeSession(state: .authenticated),
                client: PreviewCourseReviewsClient.loaded()
            )
            .preferredColorScheme(.dark)
            .previewDisplayName("Reviews Feed - Dark")

            NavigationStack {
                CourseReviewDetailScreen(
                    session: PreviewFactory.makeSession(state: .authenticated),
                    client: PreviewCourseReviewsClient.loaded(),
                    target: PreviewCourseReviewsData.target,
                    onWriteTap: { _ in }
                )
            }
            .preferredColorScheme(.dark)
            .previewDisplayName("Review Detail - Dark")
        }
    }
}
