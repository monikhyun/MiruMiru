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
        viewModel.overallRating = 4
        viewModel.difficultySelection = 3
        viewModel.workloadSelection = 1
        viewModel.wouldTakeAgain = true
        viewModel.content = "Helpful review"
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
                overallRating: 4,
                difficulty: 3,
                workload: 1,
                wouldTakeAgain: true,
                content: "Helpful review"
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

        let succeeded = await viewModel.submit()

        XCTAssertTrue(succeeded)
        XCTAssertEqual(client.updatedTargetId, PreviewCourseReviewsData.target.targetId)
        XCTAssertEqual(client.updatedPayload?.content, "Updated review text")
    }
}
