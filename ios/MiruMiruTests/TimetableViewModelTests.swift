import XCTest
@testable import MiruMiru

private final class InMemoryTimetableColorOverrideStore: TimetableColorOverrideStore {
    private var values: [String: Int] = [:]

    func colorIndex(semesterId: Int64, lectureId: Int64) -> Int? {
        values[key(semesterId: semesterId, lectureId: lectureId)]
    }

    func allColorIndices(semesterId: Int64) -> [Int64: Int] {
        values.reduce(into: [Int64: Int]()) { result, item in
            let parts = item.key.split(separator: ":")
            guard parts.count == 2,
                  Int64(parts[0]) == semesterId,
                  let lectureId = Int64(parts[1]) else {
                return
            }
            result[lectureId] = item.value
        }
    }

    func setColorIndex(_ colorIndex: Int, semesterId: Int64, lectureId: Int64) {
        values[key(semesterId: semesterId, lectureId: lectureId)] = colorIndex
    }

    func removeColorIndex(semesterId: Int64, lectureId: Int64) {
        values.removeValue(forKey: key(semesterId: semesterId, lectureId: lectureId))
    }

    private func key(semesterId: Int64, lectureId: Int64) -> String {
        "\(semesterId):\(lectureId)"
    }
}

@MainActor
final class TimetableViewModelTests: XCTestCase {
    func testLoadUsesFirstSemesterAndBuildsBlocks() async {
        let client = MockTimetableClient()
        client.memberContextResult = .success(sampleMemberContext)
        client.semestersResult = .success(sampleSemesters)
        client.timetableResult = .success(sampleTimetable)

        let viewModel = TimetableViewModel(client: client)
        await viewModel.loadIfNeeded()

        guard case let .loaded(content) = viewModel.screenState else {
            return XCTFail("Expected loaded state")
        }

        XCTAssertEqual(client.requestedSemesterId, 20261)
        XCTAssertEqual(content.selectedSemester.id, 20261)
        XCTAssertEqual(content.blocks.count, 2)
        XCTAssertEqual(content.hourRange, TimetableHourRange(startHour: 9, endHour: 18))
        XCTAssertTrue(content.addedLectureIds.contains(101))
    }

    func testLoadWithoutSemestersShowsEmptyState() async {
        let client = MockTimetableClient()
        client.memberContextResult = .success(sampleMemberContext)
        client.semestersResult = .success([])

        let viewModel = TimetableViewModel(client: client)
        await viewModel.loadIfNeeded()

        guard case let .empty(content) = viewModel.screenState else {
            return XCTFail("Expected empty state")
        }

        XCTAssertEqual(content.state, .noSemesters)
    }

    func testEmptyTimetableShowsNoLecturesState() async {
        let client = MockTimetableClient()
        client.memberContextResult = .success(sampleMemberContext)
        client.semestersResult = .success(sampleSemesters)
        client.timetableResult = .success(
            TimetableDetail(
                timetableId: nil,
                semester: sampleSemesters[0],
                lectures: []
            )
        )

        let viewModel = TimetableViewModel(client: client)
        await viewModel.loadIfNeeded()

        guard case let .empty(content) = viewModel.screenState else {
            return XCTFail("Expected empty state")
        }

        XCTAssertEqual(content.state, .noLectures)
        XCTAssertEqual(content.selectedSemester?.id, 20261)
    }

    func testSelectSemesterReloadsTimetable() async {
        let client = MockTimetableClient()
        client.memberContextResult = .success(sampleMemberContext)
        client.semestersResult = .success(sampleSemesters)
        client.timetableResult = .success(sampleTimetable)

        let viewModel = TimetableViewModel(client: client)
        await viewModel.loadIfNeeded()
        client.timetableResult = .success(
            TimetableDetail(
                timetableId: 78,
                semester: sampleSemesters[1],
                lectures: []
            )
        )

        await viewModel.selectSemester(20252)

        XCTAssertEqual(client.requestedSemesterId, 20252)
    }

    func testCatalogLoadsLazilyAndCachesPerSemester() async {
        let client = MockTimetableClient()
        client.memberContextResult = .success(sampleMemberContext)
        client.semestersResult = .success(sampleSemesters)
        client.timetableResult = .success(sampleTimetable)
        client.catalogResult = .success(sampleCatalog)

        let viewModel = TimetableViewModel(client: client)
        await viewModel.loadIfNeeded()
        await viewModel.loadCatalogIfNeeded()
        await viewModel.loadCatalogIfNeeded()

        XCTAssertEqual(client.catalogRequestedSemesterIds, [20261])
    }

    func testAddLectureRefreshesTimetableAndCatalog() async {
        let client = MockTimetableClient()
        client.memberContextResult = .success(sampleMemberContext)
        client.semestersResult = .success(sampleSemesters)
        client.timetableResult = .success(sampleTimetable)
        client.catalogResult = .success(sampleCatalog)

        let viewModel = TimetableViewModel(client: client)
        await viewModel.loadIfNeeded()
        await viewModel.loadCatalogIfNeeded()
        await viewModel.addLecture(202)

        XCTAssertEqual(client.addedPayloads.first?.semesterId, 20261)
        XCTAssertEqual(client.addedPayloads.first?.lectureId, 202)
        XCTAssertEqual(client.catalogRequestedSemesterIds, [20261, 20261])
        XCTAssertEqual(client.requestedSemesterId, 20261)
    }

    func testMakeBlocksUsesMinuteAccurateOffsets() {
        let blocks = TimetableViewModel.makeBlocks(from: sampleTimetable.lectures)
        XCTAssertEqual(blocks.count, 2)
        XCTAssertEqual(blocks[0].dayIndex, 0)
        XCTAssertEqual(blocks[1].startMinutes, 640)
        XCTAssertEqual(blocks[1].endMinutes, 720)
    }

    func testColorWheelUsesRequiredTwelveHexValues() {
        XCTAssertEqual(
            TimetableColorWheel.tokens.map(\.hex),
            [
                "#FF0000",
                "#FF4500",
                "#FFA500",
                "#FFBF00",
                "#FFFF00",
                "#7FFF00",
                "#008000",
                "#008080",
                "#0000FF",
                "#4B0082",
                "#800080",
                "#FF00FF"
            ]
        )
    }

    func testSameLectureReceivesSameColorAcrossScheduleBlocks() {
        let lecture = makeLecture(
            id: 301,
            name: "Distributed Systems",
            schedules: [
                makeSchedule(day: "MONDAY", start: "09:00", end: "10:00"),
                makeSchedule(day: "WEDNESDAY", start: "14:00", end: "15:00")
            ]
        )

        let blocks = TimetableViewModel.makeBlocks(from: [lecture])

        XCTAssertEqual(Set(blocks.map(\.accentIndex)).count, 1)
    }

    func testOverlappingLecturesAvoidColorCollisionsWhilePaletteHasCapacity() {
        let lectures = [
            makeLecture(id: 1, name: "A", schedules: [makeSchedule(day: "MONDAY", start: "09:00", end: "10:30")]),
            makeLecture(id: 2, name: "B", schedules: [makeSchedule(day: "MONDAY", start: "09:30", end: "10:40")]),
            makeLecture(id: 3, name: "C", schedules: [makeSchedule(day: "MONDAY", start: "09:45", end: "10:10")])
        ]

        let assignments = TimetableViewModel.colorAssignments(from: lectures)

        XCTAssertEqual(Set(assignments.values).count, lectures.count)
    }

    func testColorAssignmentFallsBackStablyWhenCliqueExceedsPalette() {
        let lectures = (1...13).map { id in
            makeLecture(
                id: Int64(id),
                name: "Course \(id)",
                schedules: [makeSchedule(day: "TUESDAY", start: "10:00", end: "11:00")]
            )
        }

        let first = TimetableViewModel.colorAssignments(from: lectures)
        let second = TimetableViewModel.colorAssignments(from: lectures)

        XCTAssertEqual(first, second)
        XCTAssertEqual(Set((1...12).compactMap { first[Int64($0)] }).count, TimetableColorWheel.count)
        XCTAssertNotNil(first[13])
        XCTAssertTrue(first.values.allSatisfy { 0..<TimetableColorWheel.count ~= $0 })
    }

    func testCustomColorOverridePersistsAndRejectsOverlappingDuplicateColor() async {
        let store = InMemoryTimetableColorOverrideStore()
        let client = MockTimetableClient()
        let lectures = [
            makeLecture(id: 11, name: "Morning A", schedules: [makeSchedule(day: "MONDAY", start: "09:00", end: "10:00")]),
            makeLecture(id: 22, name: "Morning B", schedules: [makeSchedule(day: "MONDAY", start: "09:30", end: "10:30")])
        ]
        client.memberContextResult = .success(sampleMemberContext)
        client.semestersResult = .success(sampleSemesters)
        client.timetableResult = .success(
            TimetableDetail(timetableId: 88, semester: sampleSemesters[0], lectures: lectures)
        )

        let viewModel = TimetableViewModel(client: client, colorOverrideStore: store)
        await viewModel.loadIfNeeded()

        XCTAssertTrue(viewModel.setCustomColorIndex(4, for: 11))
        XCTAssertEqual(viewModel.customColorIndex(for: 11), 4)
        XCTAssertFalse(viewModel.setCustomColorIndex(4, for: 22))
        XCTAssertNil(viewModel.customColorIndex(for: 22))
        XCTAssertTrue(viewModel.customColorOptions(for: 22).first { $0.token.index == 4 }?.isDisabled == true)
    }

    func testLunchMarkerUsesRequiredMinutePosition() {
        XCTAssertEqual(TimetableViewModel.lunchMarker.startMinutes, 12 * 60 + 35)
        XCTAssertEqual(TimetableViewModel.lunchMarker.endMinutes, 13 * 60 + 30)
        XCTAssertEqual(TimetableViewModel.markers(for: TimetableHourRange(startHour: 9, endHour: 18)), [TimetableViewModel.lunchMarker])
    }

    func testHourRangeExtendsToTwentyOneOnlyForLateLectures() {
        let normal = [makeLecture(id: 1, name: "Normal", schedules: [makeSchedule(day: "MONDAY", start: "09:00", end: "18:00")])]
        let late = [makeLecture(id: 2, name: "Late", schedules: [makeSchedule(day: "MONDAY", start: "17:30", end: "18:10")])]
        let veryLate = [makeLecture(id: 3, name: "Very Late", schedules: [makeSchedule(day: "MONDAY", start: "20:30", end: "22:00")])]

        XCTAssertEqual(TimetableViewModel.hourRange(from: normal), TimetableHourRange(startHour: 9, endHour: 18))
        XCTAssertEqual(TimetableViewModel.hourRange(from: late), TimetableHourRange(startHour: 9, endHour: 21))
        XCTAssertEqual(TimetableViewModel.hourRange(from: veryLate), TimetableHourRange(startHour: 9, endHour: 21))
        XCTAssertEqual(
            TimetableViewModel.makeBlocks(from: veryLate, displayEndMinutes: 21 * 60).first?.endMinutes,
            21 * 60
        )
    }

    func testNonEmptyTimetableAfterDisplayCapDoesNotShowNoLecturesState() async {
        let client = MockTimetableClient()
        let lectureAfterDisplayCap = makeLecture(
            id: 4,
            name: "Night Seminar",
            schedules: [makeSchedule(day: "MONDAY", start: "21:30", end: "22:00")]
        )
        client.memberContextResult = .success(sampleMemberContext)
        client.semestersResult = .success(sampleSemesters)
        client.timetableResult = .success(
            TimetableDetail(
                timetableId: 90,
                semester: sampleSemesters[0],
                lectures: [lectureAfterDisplayCap]
            )
        )

        let viewModel = TimetableViewModel(client: client)
        await viewModel.loadIfNeeded()

        guard case let .loaded(content) = viewModel.screenState else {
            return XCTFail("Expected loaded state for a non-empty timetable")
        }
        XCTAssertEqual(content.lectures.map(\.id), [4])
        XCTAssertTrue(content.blocks.isEmpty)
    }

    func testExplicitMajorPickerFiltering() async {
        let client = MockTimetableClient()
        let catalog = [
            makeLecture(id: 1, name: "CS Course", major: TimetableMajorSummary(majorId: 1, code: "CS", name: "Computer Science")),
            makeLecture(id: 2, name: "Math Course", major: TimetableMajorSummary(majorId: 2, code: "MATH", name: "Mathematics")),
            makeLecture(id: 3, name: "General Course", major: nil)
        ]
        client.memberContextResult = .success(sampleMemberContext)
        client.semestersResult = .success(sampleSemesters)
        client.timetableResult = .success(sampleTimetable)
        client.catalogResult = .success(catalog)

        let viewModel = TimetableViewModel(client: client)
        await viewModel.loadIfNeeded()
        await viewModel.loadCatalogIfNeeded()

        XCTAssertEqual(viewModel.filteredCatalog(query: "", filter: .memberMajor).map(\.id), [1])
        XCTAssertEqual(viewModel.filteredCatalog(query: "", filter: .general).map(\.id), [3])
        XCTAssertEqual(viewModel.filteredCatalog(query: "", filter: .major(code: "MATH", name: "Mathematics")).map(\.id), [2])
        XCTAssertTrue(viewModel.availableCatalogFilters.contains(.major(code: "MATH", name: "Mathematics")))
    }

    private var sampleMemberContext: TimetableMemberContext {
        TimetableMemberContext(
            memberId: 1,
            nickname: "test-user",
            email: "test@tokyo.ac.jp",
            majorCode: "CS",
            majorName: "Computer Science"
        )
    }

    private var sampleSemesters: [TimetableSemester] {
        [
            TimetableSemester(id: 20261, academicYear: 2026, term: "SPRING"),
            TimetableSemester(id: 20252, academicYear: 2025, term: "FALL")
        ]
    }

    private var sampleTimetable: TimetableDetail {
        TimetableDetail(
            timetableId: 77,
            semester: sampleSemesters[0],
            lectures: [
                TimetableLectureItem(
                    id: 101,
                    code: "CS101",
                    name: "Introduction to Computer Science",
                    professor: "Prof. Ito",
                    credit: 3,
                    major: TimetableMajorSummary(majorId: 1, code: "CS", name: "Computer Science"),
                    schedules: [
                        TimetableLectureSchedule(dayOfWeek: "MONDAY", startTime: "09:00", endTime: "10:30", location: "Room 301")
                    ]
                ),
                TimetableLectureItem(
                    id: 202,
                    code: "STAT230",
                    name: "Statistics I",
                    professor: "Prof. Ahn",
                    credit: 2,
                    major: nil,
                    schedules: [
                        TimetableLectureSchedule(dayOfWeek: "THURSDAY", startTime: "10:40", endTime: "12:00", location: "PC-2")
                    ]
                )
            ]
        )
    }

    private var sampleCatalog: [TimetableLectureItem] {
        sampleTimetable.lectures
    }

    private func makeLecture(
        id: Int64,
        code: String? = nil,
        name: String,
        professor: String = "Prof. Test",
        major: TimetableMajorSummary? = TimetableMajorSummary(majorId: 1, code: "CS", name: "Computer Science"),
        schedules: [TimetableLectureSchedule] = [TimetableLectureSchedule(dayOfWeek: "MONDAY", startTime: "09:00", endTime: "10:00", location: "Room 1")]
    ) -> TimetableLectureItem {
        TimetableLectureItem(
            id: id,
            code: code ?? "TEST\(id)",
            name: name,
            professor: professor,
            credit: 2,
            major: major,
            schedules: schedules
        )
    }

    private func makeSchedule(day: String, start: String, end: String, location: String = "Room 1") -> TimetableLectureSchedule {
        TimetableLectureSchedule(dayOfWeek: day, startTime: start, endTime: end, location: location)
    }
}
