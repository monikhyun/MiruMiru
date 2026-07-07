import XCTest
@testable import MiruMiru

@MainActor
final class HomeViewModelTests: XCTestCase {
    func testLoadSuccessUsesFirstSemesterAndBuildsRows() async {
        let client = MockHomeClient()
        client.profileResult = .success(sampleProfile)
        client.semestersResult = .success([
            HomeSemester(id: 20261, academicYear: 2026, term: "SPRING"),
            HomeSemester(id: 20252, academicYear: 2025, term: "FALL")
        ])
        client.timetableResult = .success(
            HomeTimetable(
                timetableId: 88,
                semester: HomeSemester(id: 20261, academicYear: 2026, term: "SPRING"),
                lectures: [
                    HomeLecture(
                        id: 1,
                        code: "CS101",
                        name: "Computer Science",
                        professor: "Prof. Ito",
                        schedules: [
                            HomeLectureSchedule(dayOfWeek: "WEDNESDAY", startTime: "09:00", endTime: "10:30", location: "Engineering Hall 101")
                        ]
                    )
                ]
            )
        )

        let viewModel = HomeViewModel(
            client: client,
            nowProvider: fixedDate("2026-03-18T09:15:00+09:00"),
            calendar: seoulCalendar
        )

        await viewModel.loadIfNeeded()

        guard case let .loaded(content) = viewModel.state else {
            return XCTFail("Expected loaded state")
        }

        XCTAssertEqual(client.requestedSemesterId, 20261)
        XCTAssertEqual(content.profile.nickname, "test-user")
        XCTAssertEqual(content.semesterTitle, "2026 Spring")
        XCTAssertEqual(content.todayClasses.count, 1)
        XCTAssertEqual(content.todayClasses.first?.badge, .now)
    }

    func testLoadWithoutSemestersShowsNoSemesterEmptyState() async {
        let client = MockHomeClient()
        client.profileResult = .success(sampleProfile)
        client.semestersResult = .success([])

        let viewModel = HomeViewModel(client: client)
        await viewModel.loadIfNeeded()

        guard case let .empty(content) = viewModel.state else {
            return XCTFail("Expected empty state")
        }
        XCTAssertEqual(content.state, .noSemester)
    }

    func testLoadWithoutTimetableShowsNoTimetableEmptyState() async {
        let client = MockHomeClient()
        client.profileResult = .success(sampleProfile)
        client.semestersResult = .success([HomeSemester(id: 20261, academicYear: 2026, term: "SPRING")])
        client.timetableResult = .success(
            HomeTimetable(
                timetableId: nil,
                semester: HomeSemester(id: 20261, academicYear: 2026, term: "SPRING"),
                lectures: []
            )
        )

        let viewModel = HomeViewModel(client: client)
        await viewModel.loadIfNeeded()

        guard case let .empty(content) = viewModel.state else {
            return XCTFail("Expected empty state")
        }
        XCTAssertEqual(content.state, .noTimetable)
    }

    func testLoadWithoutTodayClassesShowsNoClassesEmptyState() async {
        let client = MockHomeClient()
        client.profileResult = .success(sampleProfile)
        client.semestersResult = .success([HomeSemester(id: 20261, academicYear: 2026, term: "SPRING")])
        client.timetableResult = .success(
            HomeTimetable(
                timetableId: 7,
                semester: HomeSemester(id: 20261, academicYear: 2026, term: "SPRING"),
                lectures: [
                    HomeLecture(
                        id: 1,
                        code: "CS101",
                        name: "Computer Science",
                        professor: "Prof. Ito",
                        schedules: [
                            HomeLectureSchedule(dayOfWeek: "MONDAY", startTime: "09:00", endTime: "10:30", location: "Engineering Hall 101")
                        ]
                    )
                ]
            )
        )

        let viewModel = HomeViewModel(
            client: client,
            nowProvider: fixedDate("2026-03-18T09:15:00+09:00"),
            calendar: seoulCalendar
        )
        await viewModel.loadIfNeeded()

        guard case let .empty(content) = viewModel.state else {
            return XCTFail("Expected empty state")
        }
        XCTAssertEqual(content.state, .noClassesToday)
    }

    func testUnauthorizedMapsToInvalidSessionFailure() async {
        let client = MockHomeClient()
        client.profileResult = .failure(HomeClientError.invalidSession)

        let viewModel = HomeViewModel(client: client)
        await viewModel.loadIfNeeded()

        XCTAssertEqual(viewModel.state, .failed(.invalidSession))
        XCTAssertTrue(viewModel.invalidateStateIfNeeded())
    }

    func testTodayClassRowsAssignNowAndNextBadges() {
        let timetable = HomeTimetable(
            timetableId: 1,
            semester: HomeSemester(id: 20261, academicYear: 2026, term: "SPRING"),
            lectures: [
                HomeLecture(
                    id: 1,
                    code: "CS101",
                    name: "Computer Science",
                    professor: "Prof. Ito",
                    schedules: [
                        HomeLectureSchedule(dayOfWeek: "WEDNESDAY", startTime: "09:00", endTime: "10:30", location: "Engineering Hall 101")
                    ]
                ),
                HomeLecture(
                    id: 2,
                    code: "MATH201",
                    name: "Applied Mathematics",
                    professor: "Prof. Sakamoto",
                    schedules: [
                        HomeLectureSchedule(dayOfWeek: "WEDNESDAY", startTime: "13:00", endTime: "14:30", location: "Science 202")
                    ]
                )
            ]
        )

        let rows = HomeViewModel.makeTodayClassRows(
            from: timetable,
            now: fixedDate("2026-03-18T09:15:00+09:00")(),
            calendar: seoulCalendar
        )

        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0].badge, .now)
        XCTAssertEqual(rows[1].badge, .next)
    }

    func testLoadUsesDSTLocalDayAndBoundedScheduleHorizonAllRequests() async throws {
        let client = SchedulerHomeClient()
        client.profile = sampleProfile
        client.semesters = [HomeSemester(id: 20261, academicYear: 2026, term: "SPRING")]
        client.timetable = HomeTimetable(
            timetableId: 88,
            semester: HomeSemester(id: 20261, academicYear: 2026, term: "SPRING"),
            lectures: []
        )
        client.scheduleItems = [scheduleItem(itemId: 101, dueAt: fixedDateValue("2026-03-08T16:00:00Z"))]
        let now = fixedDateValue("2026-03-08T12:00:00-07:00")

        let viewModel = HomeViewModel(
            client: client,
            nowProvider: { now },
            calendar: losAngelesCalendar
        )

        await viewModel.loadIfNeeded()

        guard case let .empty(content) = viewModel.state else {
            return XCTFail("Expected no-classes empty state")
        }
        XCTAssertEqual(content.scheduleItems.map(\.itemId), [101])
        XCTAssertTrue(content.lectureOptions.isEmpty)

        let localDayRange = HomeViewModel.localDayRange(containing: now, calendar: losAngelesCalendar)
        XCTAssertEqual(localDayRange.duration, 23 * 60 * 60)
        let localDayRequest = try XCTUnwrap(client.scheduleFetchRequests.first {
            $0.from == localDayRange.start && $0.to == localDayRange.end
        })
        XCTAssertEqual(localDayRequest.from, localDayRange.start)
        XCTAssertEqual(localDayRequest.to, localDayRange.end)
        XCTAssertEqual(localDayRequest.status, .all)

        let expectedHorizon = HomeViewModel.scheduleHorizonRange(
            around: localDayRange,
            calendar: losAngelesCalendar
        )
        let horizonRequest = try XCTUnwrap(client.scheduleFetchRequests.first {
            $0.from == expectedHorizon.start && $0.to == expectedHorizon.end
        })
        XCTAssertEqual(horizonRequest.status, .all)
        XCTAssertEqual(client.scheduleFetchRequests.count, 2)
    }

    func testFutureAssignmentCompletionSurvivesReloadAndCanBeReopened() async throws {
        let client = SchedulerHomeClient()
        client.profile = sampleProfile
        client.semesters = [HomeSemester(id: 20261, academicYear: 2026, term: "SPRING")]
        client.timetable = sampleWednesdayTimetable
        client.scheduleItems = [scheduleItem(itemId: 202, dueAt: fixedDateValue("2030-06-10T08:00:00Z"))]
        let now = fixedDateValue("2026-03-18T09:15:00+09:00")

        let viewModel = HomeViewModel(
            client: client,
            nowProvider: { now },
            calendar: seoulCalendar
        )

        await viewModel.loadIfNeeded()
        let futureItem = try XCTUnwrap(viewModel.openScheduleItemsSnapshot().first)

        await viewModel.toggleScheduleItemCompletion(futureItem)
        XCTAssertEqual(viewModel.completedScheduleItemsSnapshot().map(\.itemId), [202])

        await viewModel.loadForActivation()
        XCTAssertEqual(viewModel.completedScheduleItemsSnapshot().map(\.itemId), [202])

        await viewModel.reload()
        let completedItem = try XCTUnwrap(viewModel.completedScheduleItemsSnapshot().first)
        XCTAssertEqual(completedItem.itemId, 202)

        await viewModel.toggleScheduleItemCompletion(completedItem)
        XCTAssertEqual(viewModel.openScheduleItemsSnapshot().map(\.itemId), [202])

        let todayIDs = Set(viewModel.todayDeadlinesSnapshot().map(\.itemId))
        let openIDs = Set(viewModel.openScheduleItemsSnapshot().map(\.itemId))
        let completedIDs = Set(viewModel.completedScheduleItemsSnapshot().map(\.itemId))
        XCTAssertTrue(todayIDs.isDisjoint(with: openIDs))
        XCTAssertTrue(todayIDs.isDisjoint(with: completedIDs))
        XCTAssertTrue(openIDs.isDisjoint(with: completedIDs))

        let localDayRange = HomeViewModel.localDayRange(containing: now, calendar: seoulCalendar)
        let horizon = HomeViewModel.scheduleHorizonRange(
            around: localDayRange,
            calendar: seoulCalendar
        )
        XCTAssertEqual(client.scheduleFetchRequests.count, 6)
        XCTAssertTrue(client.scheduleFetchRequests.allSatisfy { $0.status == .all })
        XCTAssertEqual(client.scheduleFetchRequests.filter {
            $0.from == localDayRange.start && $0.to == localDayRange.end
        }.count, 3)
        XCTAssertEqual(client.scheduleFetchRequests.filter {
            $0.from == horizon.start && $0.to == horizon.end
        }.count, 3)
    }

    func testScheduleDateSelectionRangeMatchesHorizonAndClampsBoundaries() {
        let now = fixedDateValue("2026-03-18T09:15:00+09:00")
        let localDayRange = HomeViewModel.localDayRange(containing: now, calendar: seoulCalendar)
        let horizon = HomeViewModel.scheduleHorizonRange(
            around: localDayRange,
            calendar: seoulCalendar
        )

        let range = HomeViewModel.scheduleDateSelectionRange(now: now, calendar: seoulCalendar)

        XCTAssertEqual(range.lowerBound, horizon.start)
        XCTAssertLessThan(range.upperBound, horizon.end)
        XCTAssertGreaterThan(range.upperBound, horizon.end.addingTimeInterval(-1))
        XCTAssertEqual(HomeViewModel.clamp(.distantPast, to: range), range.lowerBound)
        XCTAssertEqual(HomeViewModel.clamp(.distantFuture, to: range), range.upperBound)
        XCTAssertEqual(HomeViewModel.clamp(now, to: range), now)
    }

    func testTodayScheduleGroupingUsesCalendarBoundariesAndKeepsUndatedMemoOpen() {
        let now = fixedDateValue("2026-03-18T09:15:00+09:00")
        let beforeToday = scheduleItem(itemId: 1, dueAt: fixedDateValue("2026-03-17T14:59:59Z"))
        let todayStart = scheduleItem(itemId: 2, dueAt: fixedDateValue("2026-03-17T15:00:00Z"))
        let todayEnd = scheduleItem(itemId: 3, dueAt: fixedDateValue("2026-03-18T14:59:59Z"))
        let nextDay = scheduleItem(itemId: 4, dueAt: fixedDateValue("2026-03-18T15:00:00Z"))
        let memo = scheduleItem(itemId: 5, type: .memo, dueAt: nil)

        let today = HomeViewModel.todayScheduleItems(
            from: [beforeToday, todayStart, todayEnd, nextDay, memo],
            now: now,
            calendar: seoulCalendar
        )
        let todayIDs = Set(today.map(\.itemId))
        let open = HomeViewModel.openScheduleItems(
            from: [beforeToday, todayStart, todayEnd, nextDay, memo],
            todayItemIDs: todayIDs
        )

        XCTAssertEqual(today.map(\.itemId), [2, 3])
        XCTAssertTrue(open.contains { $0.itemId == memo.itemId })
        XCTAssertTrue(Set(open.map(\.itemId)).isDisjoint(with: todayIDs))
    }

    func testTodayOpenAndCompletedGroupsHaveNoSharedIDs() {
        let now = fixedDateValue("2026-03-18T09:15:00+09:00")
        let items = [
            scheduleItem(itemId: 1, dueAt: fixedDateValue("2026-03-18T05:30:00Z")),
            scheduleItem(itemId: 2, dueAt: fixedDateValue("2026-03-18T06:00:00Z"), completed: true),
            scheduleItem(itemId: 3, dueAt: fixedDateValue("2026-03-20T05:30:00Z")),
            scheduleItem(itemId: 4, type: .memo, dueAt: nil, completed: true),
            scheduleItem(itemId: 5, type: .memo, dueAt: nil)
        ]

        let today = HomeViewModel.todayScheduleItems(from: items, now: now, calendar: seoulCalendar)
        let todayIDs = Set(today.map(\.itemId))
        let open = HomeViewModel.openScheduleItems(from: items, todayItemIDs: todayIDs)
        let completed = HomeViewModel.completedScheduleItems(from: items, todayItemIDs: todayIDs)
        let openIDs = Set(open.map(\.itemId))
        let completedIDs = Set(completed.map(\.itemId))

        XCTAssertTrue(todayIDs.isDisjoint(with: openIDs))
        XCTAssertTrue(todayIDs.isDisjoint(with: completedIDs))
        XCTAssertTrue(openIDs.isDisjoint(with: completedIDs))
        XCTAssertEqual(todayIDs, Set([Int64(1), Int64(2)]))
        XCTAssertEqual(openIDs, Set([Int64(3), Int64(5)]))
        XCTAssertEqual(completedIDs, Set([Int64(4)]))
    }

    func testLocalDayRangeUsesCalendarDayAcrossDaylightSavingTransition() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let now = fixedDateValue("2026-03-08T12:00:00-07:00")

        let range = HomeViewModel.localDayRange(containing: now, calendar: calendar)

        XCTAssertEqual(range.start, fixedDateValue("2026-03-08T08:00:00Z"))
        XCTAssertEqual(range.end, fixedDateValue("2026-03-09T07:00:00Z"))
        XCTAssertEqual(range.duration, 23 * 60 * 60)
    }

    func testCompletionResponseReplacesItemInLoadedState() async {
        let client = SchedulerHomeClient()
        client.profile = sampleProfile
        client.semesters = [HomeSemester(id: 20261, academicYear: 2026, term: "SPRING")]
        client.timetable = sampleWednesdayTimetable
        let item = scheduleItem(itemId: 101, dueAt: fixedDateValue("2026-03-18T05:30:00Z"))
        client.scheduleItems = [item]

        let viewModel = HomeViewModel(
            client: client,
            nowProvider: fixedDate("2026-03-18T09:15:00+09:00"),
            calendar: seoulCalendar
        )
        await viewModel.loadIfNeeded()

        await viewModel.toggleScheduleItemCompletion(item)

        XCTAssertEqual(client.completionRequests.count, 1)
        XCTAssertEqual(client.completionRequests.first?.0, 101)
        XCTAssertEqual(client.completionRequests.first?.1, true)
        XCTAssertEqual(viewModel.scheduleItemsSnapshot().first?.completed, true)
        XCTAssertTrue(viewModel.openScheduleItemsSnapshot().isEmpty)
    }

    func testCompletedUndatedMemoCanBeReopenedEditedAndDeleted() async throws {
        let client = SchedulerHomeClient()
        client.profile = sampleProfile
        client.semesters = [HomeSemester(id: 20261, academicYear: 2026, term: "SPRING")]
        client.timetable = sampleWednesdayTimetable
        let memo = scheduleItem(itemId: 303, type: .memo, dueAt: nil)
        client.scheduleItems = [memo]

        let viewModel = HomeViewModel(
            client: client,
            nowProvider: fixedDate("2026-03-18T09:15:00+09:00"),
            calendar: seoulCalendar
        )
        await viewModel.loadIfNeeded()

        await viewModel.toggleScheduleItemCompletion(memo)
        XCTAssertTrue(viewModel.openScheduleItemsSnapshot().isEmpty)
        XCTAssertEqual(viewModel.completedScheduleItemsSnapshot().map(\.itemId), [303])

        let completedMemo = try XCTUnwrap(viewModel.completedScheduleItemsSnapshot().first)
        await viewModel.toggleScheduleItemCompletion(completedMemo)
        XCTAssertEqual(viewModel.openScheduleItemsSnapshot().map(\.itemId), [303])
        XCTAssertTrue(viewModel.completedScheduleItemsSnapshot().isEmpty)

        let reopenedMemo = try XCTUnwrap(viewModel.openScheduleItemsSnapshot().first)
        await viewModel.toggleScheduleItemCompletion(reopenedMemo)
        let completedAgain = try XCTUnwrap(viewModel.completedScheduleItemsSnapshot().first)
        let editInput = HomeScheduleItemInput(
            lectureId: nil,
            type: .memo,
            title: "Updated reminder",
            memo: "Still undated",
            dueAt: nil,
            completed: true
        )
        let edited = await viewModel.updateScheduleItem(itemId: completedAgain.itemId, input: editInput)
        XCTAssertTrue(edited)
        XCTAssertEqual(viewModel.completedScheduleItemsSnapshot().first?.title, "Updated reminder")

        await viewModel.deleteScheduleItem(try XCTUnwrap(viewModel.completedScheduleItemsSnapshot().first))
        XCTAssertTrue(viewModel.completedScheduleItemsSnapshot().isEmpty)
        XCTAssertEqual(client.deletedItemIds, [303])
    }

    func testScheduleItemsRemainAvailableInNoClassesEmptyState() async {
        let client = SchedulerHomeClient()
        client.profile = sampleProfile
        client.semesters = [HomeSemester(id: 20261, academicYear: 2026, term: "SPRING")]
        client.timetable = HomeTimetable(
            timetableId: 7,
            semester: HomeSemester(id: 20261, academicYear: 2026, term: "SPRING"),
            lectures: [
                HomeLecture(
                    id: 1,
                    code: "CS101",
                    name: "Computer Science",
                    professor: "Prof. Ito",
                    schedules: [
                        HomeLectureSchedule(
                            dayOfWeek: "MONDAY",
                            startTime: "09:00",
                            endTime: "10:30",
                            location: "Engineering Hall 101"
                        )
                    ]
                )
            ]
        )
        client.scheduleItems = [scheduleItem(itemId: 55, type: .memo, dueAt: nil)]

        let viewModel = HomeViewModel(
            client: client,
            nowProvider: fixedDate("2026-03-18T09:15:00+09:00"),
            calendar: seoulCalendar
        )
        await viewModel.loadIfNeeded()

        guard case let .empty(content) = viewModel.state else {
            return XCTFail("Expected empty state")
        }
        XCTAssertEqual(content.state, .noClassesToday)
        XCTAssertEqual(content.scheduleItems.map(\.itemId), [55])
        XCTAssertEqual(viewModel.openScheduleItemsSnapshot().map(\.itemId), [55])
    }

    func testCreateUpdateAndDeleteMutateVisibleScheduleState() async throws {
        let client = SchedulerHomeClient()
        client.profile = sampleProfile
        client.semesters = [HomeSemester(id: 20261, academicYear: 2026, term: "SPRING")]
        client.timetable = sampleWednesdayTimetable

        let viewModel = HomeViewModel(
            client: client,
            nowProvider: fixedDate("2026-03-18T09:15:00+09:00"),
            calendar: seoulCalendar
        )
        await viewModel.loadIfNeeded()

        let input = HomeScheduleItemInput(
            lectureId: nil,
            type: .memo,
            title: "Bring calculator",
            memo: nil,
            dueAt: nil,
            completed: false
        )
        let createdSuccessfully = await viewModel.createScheduleItem(input)
        XCTAssertTrue(createdSuccessfully)
        let created = try XCTUnwrap(viewModel.scheduleItemsSnapshot().first)

        let updatedInput = HomeScheduleItemInput(
            lectureId: 1,
            type: .assignment,
            title: "Submit worksheet",
            memo: nil,
            dueAt: fixedDateValue("2026-03-18T05:30:00Z"),
            completed: false
        )
        let updatedSuccessfully = await viewModel.updateScheduleItem(itemId: created.itemId, input: updatedInput)
        XCTAssertTrue(updatedSuccessfully)
        XCTAssertEqual(viewModel.scheduleItemsSnapshot().first?.title, "Submit worksheet")

        await viewModel.deleteScheduleItem(try XCTUnwrap(viewModel.scheduleItemsSnapshot().first))
        XCTAssertTrue(viewModel.scheduleItemsSnapshot().isEmpty)
        XCTAssertEqual(client.deletedItemIds, [created.itemId])
    }

    private var sampleProfile: HomeMemberProfile {
        HomeMemberProfile(
            memberId: 1,
            email: "test@tokyo.ac.jp",
            nickname: "test-user",
            universityName: "The University of Tokyo",
            universityEmailDomain: "tokyo.ac.jp",
            majorCode: "CS",
            majorName: "Computer Science"
        )
    }

    private var sampleWednesdayTimetable: HomeTimetable {
        HomeTimetable(
            timetableId: 88,
            semester: HomeSemester(id: 20261, academicYear: 2026, term: "SPRING"),
            lectures: [
                HomeLecture(
                    id: 1,
                    code: "CS101",
                    name: "Computer Science",
                    professor: "Prof. Ito",
                    schedules: [
                        HomeLectureSchedule(
                            dayOfWeek: "WEDNESDAY",
                            startTime: "09:00",
                            endTime: "10:30",
                            location: "Engineering Hall 101"
                        )
                    ]
                )
            ]
        )
    }

    private var seoulCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return calendar
    }

    private var losAngelesCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar
    }

    private func fixedDate(_ value: String) -> @Sendable () -> Date {
        {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime]
            return formatter.date(from: value)!
        }
    }

    private func fixedDateValue(_ value: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)!
    }

    private func scheduleItem(
        itemId: Int64,
        type: HomeScheduleItemType = .assignment,
        dueAt: Date?,
        completed: Bool = false
    ) -> HomeScheduleItem {
        HomeScheduleItem(
            itemId: itemId,
            lectureId: nil,
            lectureName: nil,
            type: type,
            title: "Item \(itemId)",
            memo: type == .memo ? "Remember this" : nil,
            dueAt: dueAt,
            completed: completed,
            createdAt: fixedDateValue("2026-03-17T03:00:00Z"),
            updatedAt: fixedDateValue("2026-03-17T03:00:00Z")
        )
    }
}

private struct ScheduleFetchRequest: Equatable {
    let from: Date
    let to: Date
    let status: HomeScheduleItemStatus
}

private final class SchedulerHomeClient: HomeClientProtocol, @unchecked Sendable {
    private let lock = NSLock()

    var profile = HomeMemberProfile(
        memberId: 1,
        email: "test@tokyo.ac.jp",
        nickname: "test-user",
        universityName: "The University of Tokyo",
        universityEmailDomain: "tokyo.ac.jp",
        majorCode: "CS",
        majorName: "Computer Science"
    )
    var semesters: [HomeSemester] = []
    var timetable = HomeTimetable(
        timetableId: nil,
        semester: HomeSemester(id: 0, academicYear: 2026, term: "SPRING"),
        lectures: []
    )
    var scheduleItems: [HomeScheduleItem] = []

    private(set) var scheduleFetchRequests: [ScheduleFetchRequest] = []
    private(set) var completionRequests: [(Int64, Bool)] = []
    private(set) var deletedItemIds: [Int64] = []
    private var nextItemId: Int64 = 1_000

    func fetchProfile() async throws -> HomeMemberProfile { profile }
    func fetchSemesters() async throws -> [HomeSemester] { semesters }
    func fetchTimetable(semesterId: Int64) async throws -> HomeTimetable { timetable }
    func fetchHotPosts() async throws -> [HotPostSummary] { [] }

    func fetchScheduleItems(
        from: Date,
        to: Date,
        status: HomeScheduleItemStatus
    ) async throws -> [HomeScheduleItem] {
        let items = lock.withLock {
            scheduleFetchRequests.append(
                ScheduleFetchRequest(from: from, to: to, status: status)
            )
            return scheduleItems
        }

        return items.filter { item in
            let isInRange = item.dueAt.map { dueAt in
                from <= dueAt && dueAt < to
            } ?? true
            guard isInRange else { return false }

            switch status {
            case .all:
                return true
            case .open:
                return !item.completed
            case .completed:
                return item.completed
            }
        }
    }

    func createScheduleItem(_ input: HomeScheduleItemInput) async throws -> HomeScheduleItem {
        let item = makeItem(itemId: nextItemId, input: input)
        nextItemId += 1
        scheduleItems.append(item)
        return item
    }

    func updateScheduleItem(itemId: Int64, input: HomeScheduleItemInput) async throws -> HomeScheduleItem {
        let item = makeItem(itemId: itemId, input: input)
        if let index = scheduleItems.firstIndex(where: { $0.itemId == itemId }) {
            scheduleItems[index] = item
        }
        return item
    }

    func setScheduleItemCompletion(itemId: Int64, completed: Bool) async throws -> HomeScheduleItem {
        completionRequests.append((itemId, completed))
        guard let item = scheduleItems.first(where: { $0.itemId == itemId }) else {
            throw HomeClientError.unexpected
        }
        let input = HomeScheduleItemInput(
            lectureId: item.lectureId,
            type: item.type,
            title: item.title,
            memo: item.memo,
            dueAt: item.dueAt,
            completed: completed
        )
        let updated = makeItem(itemId: itemId, input: input)
        if let index = scheduleItems.firstIndex(where: { $0.itemId == itemId }) {
            scheduleItems[index] = updated
        }
        return updated
    }

    func deleteScheduleItem(itemId: Int64) async throws {
        deletedItemIds.append(itemId)
        scheduleItems.removeAll { $0.itemId == itemId }
    }

    private func makeItem(itemId: Int64, input: HomeScheduleItemInput) -> HomeScheduleItem {
        HomeScheduleItem(
            itemId: itemId,
            lectureId: input.lectureId,
            lectureName: input.lectureId == nil ? nil : "Computer Science",
            type: input.type,
            title: input.title,
            memo: input.memo,
            dueAt: input.dueAt,
            completed: input.completed,
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 2)
        )
    }
}
