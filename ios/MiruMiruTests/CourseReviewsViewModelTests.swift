import XCTest
@testable import MiruMiru

@MainActor
final class CourseReviewsViewModelTests: XCTestCase {
    func testFeedViewModelLoadsFeedItems() async {
        let client = MockCourseReviewsClient()
        client.feedResult = .success(
            CourseReviewFeedPage(
                items: [PreviewCourseReviewsData.feedPage.items[0]],
                page: 0,
                size: 20,
                totalElements: 1,
                totalPages: 1,
                hasNext: false
            )
        )

        let viewModel = CourseReviewsFeedViewModel(client: client)

        await viewModel.loadIfNeeded()

        XCTAssertEqual(viewModel.visibleItems.count, 1)
        XCTAssertEqual(client.requestedFeedPage, 0)
        XCTAssertNil(viewModel.failure)
    }

    func testFeedViewModelLiberalArtsFilterUsesDerivedCategory() async {
        let client = MockCourseReviewsClient()
        client.feedResult = .success(PreviewCourseReviewsData.feedPage)

        let viewModel = CourseReviewsFeedViewModel(client: client)
        await viewModel.loadIfNeeded()
        viewModel.selectedFilter = .liberalArts

        XCTAssertEqual(viewModel.visibleItems.map(\.target.courseCode), ["HIST120"])
    }

    func testFeedViewModelKeepsClassAndProfessorRatingsSeparate() async {
        let client = MockCourseReviewsClient()
        client.feedResult = .success(PreviewCourseReviewsData.feedPage)

        let viewModel = CourseReviewsFeedViewModel(client: client)
        await viewModel.loadIfNeeded()

        let first = viewModel.visibleItems[0]
        XCTAssertEqual(first.overallRating, 10)
        XCTAssertEqual(first.professorRating, 9)
        XCTAssertEqual(first.content, "The professor's explanations are engaging, and you can build a solid foundation in economics. Exams are open-book and the pacing feels fair.")
        XCTAssertEqual(first.professorContent, "Prof. Tanaka makes dense concepts feel approachable and keeps office hours useful.")
    }

    func testDetailViewModelKeepsPageWhenMyReviewLookupFails() async {
        let client = MockCourseReviewsClient()
        client.detailResult = .success(PreviewCourseReviewsData.detailPage)
        client.myReviewResult = .failure(CourseReviewsClientError.network)

        let viewModel = CourseReviewDetailViewModel(
            client: client,
            target: PreviewCourseReviewsData.target
        )

        await viewModel.loadIfNeeded()

        XCTAssertEqual(viewModel.page?.summary.target.targetId, PreviewCourseReviewsData.target.targetId)
        XCTAssertNil(viewModel.myReview)
        XCTAssertNil(viewModel.failure)
    }

    func testWriteReviewSubmitCreatesWhenNoExistingReview() async {
        let client = MockCourseReviewsClient()
        client.myReviewResult = .failure(CourseReviewsClientError.reviewNotFound)
        client.createResult = .success(99)

        let viewModel = WriteReviewViewModel(
            client: client,
            target: PreviewCourseReviewsData.target
        )

        await viewModel.loadIfNeeded()
        viewModel.overallRating = 8
        viewModel.professorRating = 9
        viewModel.difficultySelection = 3
        viewModel.workloadSelection = 1
        viewModel.wouldTakeAgain = true
        viewModel.content = "Helpful review"
        viewModel.professorContent = "Clear professor"
        viewModel.academicYear = 2025
        viewModel.term = .fall

        let succeeded = await viewModel.submit()

        XCTAssertTrue(succeeded)
        XCTAssertEqual(client.createdTargetId, PreviewCourseReviewsData.target.targetId)
        XCTAssertEqual(
            client.createdPayload,
                CourseReviewUpsertRequest(
                    academicYear: 2025,
                    term: "FALL",
                    overallRating: 8,
                    professorRating: 9,
                    difficulty: 3,
                    workload: 1,
                    wouldTakeAgain: true,
                    content: "Helpful review",
                    professorContent: "Clear professor"
                )
        )
    }

    func testWriteReviewSubmitUpdatesWhenExistingReviewExists() async {
        let client = MockCourseReviewsClient()
        client.myReviewResult = .success(PreviewCourseReviewsData.myReview)
        client.updateResult = .success(PreviewCourseReviewsData.myReview.reviewId)

        let viewModel = WriteReviewViewModel(
            client: client,
            target: PreviewCourseReviewsData.target
        )

        await viewModel.loadIfNeeded()
        viewModel.content = "Updated review text"
        viewModel.professorContent = "Updated professor text"

        let succeeded = await viewModel.submit()

        XCTAssertTrue(succeeded)
        XCTAssertEqual(client.updatedTargetId, PreviewCourseReviewsData.target.targetId)
        XCTAssertEqual(client.updatedPayload?.overallRating, 8)
        XCTAssertEqual(client.updatedPayload?.professorRating, 9)
        XCTAssertEqual(client.updatedPayload?.content, "Updated review text")
        XCTAssertEqual(client.updatedPayload?.professorContent, "Updated professor text")
    }
}
