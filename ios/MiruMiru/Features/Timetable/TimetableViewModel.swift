import Foundation

protocol TimetableColorOverrideStore: AnyObject {
    func colorIndex(semesterId: Int64, lectureId: Int64) -> Int?
    func allColorIndices(semesterId: Int64) -> [Int64: Int]
    func setColorIndex(_ colorIndex: Int, semesterId: Int64, lectureId: Int64)
    func removeColorIndex(semesterId: Int64, lectureId: Int64)
}

final class UserDefaultsTimetableColorOverrideStore: TimetableColorOverrideStore {
    private let defaults: UserDefaults
    private let storageKey = "MiruMiru.Timetable.colorOverrides.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func colorIndex(semesterId: Int64, lectureId: Int64) -> Int? {
        allColorIndices(semesterId: semesterId)[lectureId]
    }

    func allColorIndices(semesterId: Int64) -> [Int64: Int] {
        storedOverrides().reduce(into: [Int64: Int]()) { result, item in
            let parts = item.key.split(separator: ":")
            guard parts.count == 2,
                  Int64(parts[0]) == semesterId,
                  let lectureId = Int64(parts[1]) else {
                return
            }
            result[lectureId] = TimetableColorWheel.normalizedIndex(item.value)
        }
    }

    func setColorIndex(_ colorIndex: Int, semesterId: Int64, lectureId: Int64) {
        var overrides = storedOverrides()
        overrides[key(semesterId: semesterId, lectureId: lectureId)] = TimetableColorWheel.normalizedIndex(colorIndex)
        defaults.set(overrides, forKey: storageKey)
    }

    func removeColorIndex(semesterId: Int64, lectureId: Int64) {
        var overrides = storedOverrides()
        overrides.removeValue(forKey: key(semesterId: semesterId, lectureId: lectureId))
        defaults.set(overrides, forKey: storageKey)
    }

    private func storedOverrides() -> [String: Int] {
        defaults.dictionary(forKey: storageKey) as? [String: Int] ?? [:]
    }

    private func key(semesterId: Int64, lectureId: Int64) -> String {
        "\(semesterId):\(lectureId)"
    }
}

@MainActor
final class TimetableViewModel: ObservableObject {
    @Published private(set) var screenState: TimetableScreenState = .loading
    @Published private(set) var semesters: [TimetableSemester] = []
    @Published private(set) var selectedSemesterId: Int64?
    @Published private(set) var catalogState: TimetableCatalogState = .idle
    @Published private(set) var actionMessage: String?
    @Published private(set) var catalogActionMessage: String?

    private let client: TimetableClientProtocol
    private let colorOverrideStore: TimetableColorOverrideStore
    private var hasLoaded = false
    private var memberContext: TimetableMemberContext?
    private var currentTimetable: TimetableDetail?
    private var currentHourRange = TimetableHourRange(startHour: 9, endHour: 18)
    private var lectureCatalogCache: [Int64: [TimetableLectureItem]] = [:]

    enum TimetableActionOrigin {
        case screen
        case catalog
    }

    init(
        client: TimetableClientProtocol,
        colorOverrideStore: TimetableColorOverrideStore = UserDefaultsTimetableColorOverrideStore()
    ) {
        self.client = client
        self.colorOverrideStore = colorOverrideStore
    }

    func loadIfNeeded() async {
        guard hasLoaded == false else { return }
        hasLoaded = true
        await loadInitialData()
    }

    func reload() async {
        await client.invalidateCache()
        lectureCatalogCache.removeAll()
        catalogState = .idle
        await loadCurrentSemester(forceReloadCatalog: false)
    }

    func selectSemester(_ semesterId: Int64) async {
        guard selectedSemesterId != semesterId else { return }
        selectedSemesterId = semesterId
        actionMessage = nil
        clearCatalogActionMessage()
        catalogState = .idle
        await loadCurrentSemester(forceReloadCatalog: false)
    }

    func loadCatalogIfNeeded(forceRefresh: Bool = false) async {
        guard let semesterId = selectedSemesterId else { return }

        if forceRefresh == false, let cached = lectureCatalogCache[semesterId] {
            catalogState = .loaded(cached)
            return
        }

        catalogState = .loading

        do {
            let catalog = try await client.fetchLectureCatalog(semesterId: semesterId)
            lectureCatalogCache[semesterId] = catalog
            catalogState = .loaded(catalog)
        } catch let error as TimetableClientError {
            let failure = Self.map(error)
            if failure == .invalidSession {
                screenState = .failed(.invalidSession)
            } else {
                catalogState = .failed(failure)
            }
        } catch {
            catalogState = .failed(.unexpected)
        }
    }

    func filteredCatalog(
        query: String,
        filter: TimetableCatalogFilter
    ) -> [TimetableLectureItem] {
        guard case let .loaded(items) = catalogState else { return [] }

        let filteredByCategory = items.filter { item in
            switch filter {
            case .all:
                return true
            case .memberMajor:
                return item.major?.code == memberContext?.majorCode
            case .general:
                return item.major == nil
            case let .major(code, _):
                return item.major?.code == code
            }
        }

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            return filteredByCategory
        }

        return filteredByCategory.filter { item in
            item.name.localizedCaseInsensitiveContains(trimmed)
                || item.professor.localizedCaseInsensitiveContains(trimmed)
                || item.code.localizedCaseInsensitiveContains(trimmed)
        }
    }

    var availableCatalogFilters: [TimetableCatalogFilter] {
        let baseFilters: [TimetableCatalogFilter] = [.all, .memberMajor, .general]

        guard case let .loaded(items) = catalogState else {
            return baseFilters
        }

        var majorsByCode: [String: TimetableMajorSummary] = [:]
        for major in items.compactMap(\.major) {
            majorsByCode[major.code] = major
        }

        let explicitMajorFilters = majorsByCode.values
            .sorted {
                if $0.name == $1.name {
                    return $0.code < $1.code
                }
                return $0.name < $1.name
            }
            .map { TimetableCatalogFilter.major(code: $0.code, name: $0.name) }

        return baseFilters + explicitMajorFilters
    }

    func isLectureAdded(_ lectureId: Int64) -> Bool {
        currentTimetable?.lectures.contains(where: { $0.id == lectureId }) == true
    }

    func customColorIndex(for lectureId: Int64) -> Int? {
        guard let semesterId = selectedSemesterId else { return nil }
        return colorOverrideStore.colorIndex(semesterId: semesterId, lectureId: lectureId)
    }

    func customColorOptions(for lectureId: Int64) -> [TimetableColorPickerOption] {
        guard let timetable = currentTimetable,
              let semesterId = selectedSemesterId,
              timetable.lectures.contains(where: { $0.id == lectureId }) else {
            return TimetableColorWheel.tokens.map {
                TimetableColorPickerOption(token: $0, isSelected: false, isDisabled: false)
            }
        }

        var overrides = colorOverrideStore.allColorIndices(semesterId: semesterId)
        let selectedIndex = overrides[lectureId]
        overrides.removeValue(forKey: lectureId)

        let assignments = Self.colorAssignments(from: timetable.lectures, colorOverrides: overrides)
        let unavailable = Set(
            Self.overlappingLectureIds(for: lectureId, in: timetable.lectures).compactMap { assignments[$0] }
        )

        return TimetableColorWheel.tokens.map { token in
            let isSelected = selectedIndex == token.index
            return TimetableColorPickerOption(
                token: token,
                isSelected: isSelected,
                isDisabled: unavailable.contains(token.index) && isSelected == false
            )
        }
    }

    @discardableResult
    func setCustomColorIndex(_ colorIndex: Int, for lectureId: Int64) -> Bool {
        guard let semesterId = selectedSemesterId,
              currentTimetable?.lectures.contains(where: { $0.id == lectureId }) == true else {
            return false
        }

        let normalizedIndex = TimetableColorWheel.normalizedIndex(colorIndex)
        let option = customColorOptions(for: lectureId).first { $0.token.index == normalizedIndex }
        guard option?.isDisabled != true else {
            actionMessage = "That color is already used by an overlapping course."
            return false
        }

        colorOverrideStore.setColorIndex(normalizedIndex, semesterId: semesterId, lectureId: lectureId)
        refreshCurrentTimetablePresentation()
        return true
    }

    func clearCustomColorIndex(for lectureId: Int64) {
        guard let semesterId = selectedSemesterId else { return }
        colorOverrideStore.removeColorIndex(semesterId: semesterId, lectureId: lectureId)
        refreshCurrentTimetablePresentation()
    }

    func addLecture(_ lectureId: Int64, origin: TimetableActionOrigin = .screen) async {
        guard let semesterId = selectedSemesterId else { return }
        actionMessage = nil
        clearCatalogActionMessage()

        do {
            try await client.addLecture(semesterId: semesterId, lectureId: lectureId)
            await loadCurrentSemester(forceReloadCatalog: true)
        } catch let error as TimetableClientError {
            handleActionError(error, origin: origin)
        } catch {
            let failure = TimetableFailure.unexpected
            setActionMessage(failure.message, origin: origin)
        }
    }

    func removeLecture(_ lectureId: Int64, origin: TimetableActionOrigin = .screen) async {
        guard let semesterId = selectedSemesterId else { return }
        actionMessage = nil
        clearCatalogActionMessage()

        do {
            try await client.removeLecture(semesterId: semesterId, lectureId: lectureId)
            await loadCurrentSemester(forceReloadCatalog: true)
        } catch let error as TimetableClientError {
            handleActionError(error, origin: origin)
        } catch {
            setActionMessage(TimetableFailure.unexpected.message, origin: origin)
        }
    }

    func invalidateStateIfNeeded() -> Bool {
        if case .failed(.invalidSession) = screenState {
            return true
        }
        return false
    }

    func clearActionMessage() {
        actionMessage = nil
    }

    func clearCatalogActionMessage() {
        catalogActionMessage = nil
    }

    func clearCatalogFailure() {
        if case .failed = catalogState {
            catalogState = .idle
        }
    }

    private func handleActionError(_ error: TimetableClientError, origin: TimetableActionOrigin = .screen) {
        let failure = Self.map(error)
        if failure == .invalidSession {
            screenState = .failed(.invalidSession)
            return
        }
        setActionMessage(failure.message, origin: origin)
    }

    private func setActionMessage(_ message: String, origin: TimetableActionOrigin) {
        switch origin {
        case .screen:
            actionMessage = message
        case .catalog:
            catalogActionMessage = message
        }
    }

    private func loadInitialData() async {
        screenState = .loading

        do {
            async let memberTask = client.fetchMemberContext()
            async let semestersTask = client.fetchSemesters()

            let (memberContext, semesters) = try await (memberTask, semestersTask)
            self.memberContext = memberContext
            self.semesters = semesters

            guard let firstSemester = semesters.first else {
                currentTimetable = nil
                currentHourRange = TimetableHourRange(startHour: 9, endHour: 18)
                screenState = .empty(
                    TimetableEmptyContent(
                        memberContext: memberContext,
                        selectedSemester: nil,
                        hourRange: currentHourRange,
                        markers: Self.markers(for: currentHourRange),
                        state: .noSemesters
                    )
                )
                return
            }

            if selectedSemesterId == nil {
                selectedSemesterId = firstSemester.id
            }

            await loadCurrentSemester(forceReloadCatalog: false)
        } catch let error as TimetableClientError {
            screenState = .failed(Self.map(error))
        } catch {
            screenState = .failed(.unexpected)
        }
    }

    private func loadCurrentSemester(forceReloadCatalog: Bool) async {
        guard let semesterId = selectedSemesterId else {
            screenState = .empty(
                TimetableEmptyContent(
                    memberContext: memberContext,
                    selectedSemester: nil,
                    hourRange: TimetableHourRange(startHour: 9, endHour: 18),
                    markers: Self.markers(for: TimetableHourRange(startHour: 9, endHour: 18)),
                    state: .noSemesters
                )
            )
            return
        }

        if memberContext == nil || semesters.isEmpty {
            await loadInitialData()
            return
        }

        screenState = .loading

        do {
            let timetable = try await client.fetchMyTimetable(semesterId: semesterId)
            currentTimetable = timetable
            currentHourRange = Self.hourRange(from: timetable.lectures)
            let selectedSemester = semesters.first(where: { $0.id == semesterId }) ?? timetable.semester
            presentTimetable(timetable, selectedSemester: selectedSemester)

            if forceReloadCatalog {
                await loadCatalogIfNeeded(forceRefresh: true)
            }
        } catch let error as TimetableClientError {
            screenState = .failed(Self.map(error))
        } catch {
            screenState = .failed(.unexpected)
        }
    }

    private func refreshCurrentTimetablePresentation() {
        guard let timetable = currentTimetable,
              let semesterId = selectedSemesterId else {
            return
        }
        let selectedSemester = semesters.first(where: { $0.id == semesterId }) ?? timetable.semester
        presentTimetable(timetable, selectedSemester: selectedSemester)
    }

    private func presentTimetable(_ timetable: TimetableDetail, selectedSemester: TimetableSemester) {
        currentHourRange = Self.hourRange(from: timetable.lectures)
        let addedLectureIds = Set(timetable.lectures.map(\.id))
        let overrides: [Int64: Int]
        if let semesterId = selectedSemesterId {
            overrides = colorOverrideStore.allColorIndices(semesterId: semesterId)
        } else {
            overrides = [:]
        }
        let blocks = Self.makeBlocks(
            from: timetable.lectures,
            colorOverrides: overrides,
            displayEndMinutes: currentHourRange.endHour * 60
        )
        let markers = Self.markers(for: currentHourRange)

        if timetable.lectures.isEmpty {
            screenState = .empty(
                TimetableEmptyContent(
                    memberContext: memberContext,
                    selectedSemester: selectedSemester,
                    hourRange: currentHourRange,
                    markers: markers,
                    state: .noLectures
                )
            )
        } else if let memberContext {
            screenState = .loaded(
                TimetableLoadedContent(
                    memberContext: memberContext,
                    selectedSemester: selectedSemester,
                    timetableId: timetable.timetableId,
                    lectures: timetable.lectures,
                    blocks: blocks,
                    markers: markers,
                    addedLectureIds: addedLectureIds,
                    hourRange: currentHourRange
                )
            )
        }
    }

    static func makeBlocks(
        from lectures: [TimetableLectureItem],
        colorOverrides: [Int64: Int] = [:],
        displayEndMinutes: Int? = nil
    ) -> [TimetableGridBlock] {
        let assignments = colorAssignments(from: lectures, colorOverrides: colorOverrides)

        return lectures.flatMap { lecture in
            lecture.schedules.compactMap { schedule in
                guard let dayIndex = dayIndex(for: schedule.dayOfWeek),
                      let startMinutes = minutes(from: schedule.startTime),
                      let endMinutes = minutes(from: schedule.endTime),
                      endMinutes > startMinutes else {
                    return nil
                }
                let cappedEndMinutes = min(endMinutes, displayEndMinutes ?? endMinutes)
                guard cappedEndMinutes > startMinutes else { return nil }

                return TimetableGridBlock(
                    id: "\(lecture.id)-\(schedule.dayOfWeek)-\(schedule.startTime)",
                    lectureId: lecture.id,
                    title: lecture.name,
                    professor: lecture.professor,
                    location: schedule.location,
                    dayIndex: dayIndex,
                    startMinutes: startMinutes,
                    endMinutes: cappedEndMinutes,
                    accentIndex: assignments[lecture.id] ?? fallbackColorIndex(for: lecture.id)
                )
            }
        }
        .sorted {
            if $0.dayIndex == $1.dayIndex {
                return $0.startMinutes < $1.startMinutes
            }
            return $0.dayIndex < $1.dayIndex
        }
    }

    static func colorAssignments(
        from lectures: [TimetableLectureItem],
        colorOverrides: [Int64: Int] = [:]
    ) -> [Int64: Int] {
        let lectureIds = Set(lectures.map(\.id))
        var overlappingIdsByLecture: [Int64: Set<Int64>] = [:]

        for lecture in lectures {
            overlappingIdsByLecture[lecture.id] = []
        }

        for leftIndex in lectures.indices {
            for rightIndex in lectures.indices where rightIndex > leftIndex {
                let left = lectures[leftIndex]
                let right = lectures[rightIndex]
                guard lecturesOverlap(left, right) else { continue }
                overlappingIdsByLecture[left.id, default: []].insert(right.id)
                overlappingIdsByLecture[right.id, default: []].insert(left.id)
            }
        }

        var assignments: [Int64: Int] = [:]
        let sortedLectures = lectures.sorted {
            let lhsStart = earliestStartMinutes(for: $0) ?? .max
            let rhsStart = earliestStartMinutes(for: $1) ?? .max
            if lhsStart == rhsStart {
                return $0.id < $1.id
            }
            return lhsStart < rhsStart
        }

        for lecture in sortedLectures {
            let usedByNeighbors = Set(
                (overlappingIdsByLecture[lecture.id] ?? []).compactMap { assignments[$0] }
            )
            let overrideIndex = colorOverrides[lecture.id].map(TimetableColorWheel.normalizedIndex)

            if let overrideIndex, usedByNeighbors.contains(overrideIndex) == false {
                assignments[lecture.id] = overrideIndex
                continue
            }

            if let firstAvailable = (0..<TimetableColorWheel.count).first(where: { usedByNeighbors.contains($0) == false }) {
                assignments[lecture.id] = firstAvailable
            } else {
                assignments[lecture.id] = fallbackColorIndex(for: lecture.id)
            }
        }

        return assignments.filter { lectureIds.contains($0.key) }
    }

    static let lunchMarker = TimetableGridMarker(
        id: "lunch",
        title: "Lunch",
        startMinutes: 12 * 60 + 35,
        endMinutes: 13 * 60 + 30
    )

    static func markers(for hourRange: TimetableHourRange) -> [TimetableGridMarker] {
        let rangeStart = hourRange.startHour * 60
        let rangeEnd = hourRange.endHour * 60
        guard lunchMarker.endMinutes > rangeStart,
              lunchMarker.startMinutes < rangeEnd else {
            return []
        }
        return [lunchMarker]
    }

    static func hourRange(from lectures: [TimetableLectureItem]) -> TimetableHourRange {
        let scheduleBounds: [(Int, Int)] = lectures
            .flatMap(\.schedules)
            .compactMap { schedule in
                guard let start = minutes(from: schedule.startTime),
                      let end = minutes(from: schedule.endTime) else {
                    return nil
                }
                return (start, end)
            }

        guard let earliest = scheduleBounds.map({ $0.0 }).min(),
              let latest = scheduleBounds.map({ $0.1 }).max() else {
            return TimetableHourRange(startHour: 9, endHour: 18)
        }

        let startHour = min(9, earliest / 60)
        let endHour = latest > (18 * 60) ? 21 : 18
        return TimetableHourRange(startHour: startHour, endHour: endHour)
    }

    static func accentIndex(for lectureId: Int64) -> Int {
        fallbackColorIndex(for: lectureId)
    }

    static func fallbackColorIndex(for lectureId: Int64) -> Int {
        let mixed = UInt64(bitPattern: lectureId) &* 1_103_515_245 &+ 12_345
        return Int(mixed % UInt64(TimetableColorWheel.count))
    }

    static func minutes(from time: String) -> Int? {
        let parts = time.split(separator: ":")
        guard parts.count == 2,
              let hour = Int(parts[0]),
              let minute = Int(parts[1]) else {
            return nil
        }
        return (hour * 60) + minute
    }

    static func dayIndex(for dayOfWeek: String) -> Int? {
        switch dayOfWeek.uppercased() {
        case "MONDAY":
            return 0
        case "TUESDAY":
            return 1
        case "WEDNESDAY":
            return 2
        case "THURSDAY":
            return 3
        case "FRIDAY":
            return 4
        default:
            return nil
        }
    }

    static func overlappingLectureIds(for lectureId: Int64, in lectures: [TimetableLectureItem]) -> Set<Int64> {
        guard let targetLecture = lectures.first(where: { $0.id == lectureId }) else { return [] }
        return Set(
            lectures
                .filter { $0.id != lectureId && lecturesOverlap(targetLecture, $0) }
                .map(\.id)
        )
    }

    private static func lecturesOverlap(_ lhs: TimetableLectureItem, _ rhs: TimetableLectureItem) -> Bool {
        lhs.schedules.contains { lhsSchedule in
            rhs.schedules.contains { rhsSchedule in
                guard lhsSchedule.dayOfWeek.uppercased() == rhsSchedule.dayOfWeek.uppercased(),
                      let lhsStart = minutes(from: lhsSchedule.startTime),
                      let lhsEnd = minutes(from: lhsSchedule.endTime),
                      let rhsStart = minutes(from: rhsSchedule.startTime),
                      let rhsEnd = minutes(from: rhsSchedule.endTime) else {
                    return false
                }
                return lhsStart < rhsEnd && rhsStart < lhsEnd
            }
        }
    }

    private static func earliestStartMinutes(for lecture: TimetableLectureItem) -> Int? {
        lecture.schedules.compactMap { minutes(from: $0.startTime) }.min()
    }

    private static func map(_ error: TimetableClientError) -> TimetableFailure {
        switch error {
        case .invalidSession:
            return .invalidSession
        case .duplicateLecture:
            return .duplicateLecture
        case .timeConflict:
            return .timeConflict
        case .lectureNotFound:
            return .lectureNotFound
        case .network:
            return .network
        case .unexpected:
            return .unexpected
        }
    }
}
