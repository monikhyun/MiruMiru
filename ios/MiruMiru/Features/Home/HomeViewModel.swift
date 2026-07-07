import Foundation

@MainActor
final class HomeViewModel: ObservableObject {
    @Published private(set) var state: HomeViewState = .loading
    @Published private(set) var scheduleMutationMessage: String?

    private let client: HomeClientProtocol
    private let nowProvider: @Sendable () -> Date
    private let calendar: Calendar
    private var hasLoaded = false

    init(
        client: HomeClientProtocol,
        nowProvider: @escaping @Sendable () -> Date = Date.init,
        calendar: Calendar = .current
    ) {
        self.client = client
        self.nowProvider = nowProvider
        self.calendar = calendar
    }

    func loadIfNeeded() async {
        guard hasLoaded == false else { return }
        hasLoaded = true
        await load()
    }

    func loadForActivation() async {
        if hasLoaded {
            await load()
        } else {
            hasLoaded = true
            await load()
        }
    }

    func reload() async {
        await client.invalidateCache()
        await load()
    }

    func invalidateStateIfNeeded() -> Bool {
        if case .failed(.invalidSession) = state {
            return true
        }
        return false
    }

    func hotPostsSnapshotForSync() -> [HotPostSummary]? {
        switch state {
        case let .loaded(content):
            return content.trendingPosts
        case let .empty(content):
            return content.trendingPosts
        default:
            return nil
        }
    }

    func scheduleItemsSnapshot() -> [HomeScheduleItem] {
        switch state {
        case let .loaded(content):
            return content.scheduleItems
        case let .empty(content):
            return content.scheduleItems
        default:
            return []
        }
    }

    func lectureOptionsSnapshot() -> [HomeScheduleLectureOption] {
        switch state {
        case let .loaded(content):
            return content.lectureOptions
        case let .empty(content):
            return content.lectureOptions
        default:
            return []
        }
    }

    func todayDeadlinesSnapshot() -> [HomeScheduleItem] {
        Self.todayScheduleItems(
            from: scheduleItemsSnapshot(),
            now: nowProvider(),
            calendar: calendar
        )
    }

    func openScheduleItemsSnapshot() -> [HomeScheduleItem] {
        let items = scheduleItemsSnapshot()
        let todayItems = Self.todayScheduleItems(from: items, now: nowProvider(), calendar: calendar)
        return Self.openScheduleItems(from: items, todayItemIDs: Set(todayItems.map(\.itemId)))
    }

    func completedScheduleItemsSnapshot() -> [HomeScheduleItem] {
        let items = scheduleItemsSnapshot()
        let todayItems = Self.todayScheduleItems(from: items, now: nowProvider(), calendar: calendar)
        return Self.completedScheduleItems(from: items, todayItemIDs: Set(todayItems.map(\.itemId)))
    }

    func scheduleEditorDateConfiguration(
        for requestedDate: Date?
    ) -> (range: ClosedRange<Date>, selection: Date) {
        let now = nowProvider()
        let range = Self.scheduleDateSelectionRange(now: now, calendar: calendar)
        return (range, Self.clamp(requestedDate ?? now, to: range))
    }

    func createScheduleItem(_ input: HomeScheduleItemInput) async -> Bool {
        await performScheduleMutation {
            let item = try await client.createScheduleItem(input)
            replaceScheduleItem(item)
        }
    }

    func updateScheduleItem(itemId: Int64, input: HomeScheduleItemInput) async -> Bool {
        await performScheduleMutation {
            let item = try await client.updateScheduleItem(itemId: itemId, input: input)
            replaceScheduleItem(item)
        }
    }

    func toggleScheduleItemCompletion(_ item: HomeScheduleItem) async {
        _ = await performScheduleMutation {
            let updated = try await client.setScheduleItemCompletion(
                itemId: item.itemId,
                completed: item.completed == false
            )
            replaceScheduleItem(updated)
        }
    }

    func deleteScheduleItem(_ item: HomeScheduleItem) async {
        _ = await performScheduleMutation {
            try await client.deleteScheduleItem(itemId: item.itemId)
            mutateScheduleItems { items in
                items.removeAll { $0.itemId == item.itemId }
            }
        }
    }

    func clearScheduleMutationMessage() {
        scheduleMutationMessage = nil
    }

    private func load() async {
        state = .loading

        do {
            let now = nowProvider()
            let localDayRange = Self.localDayRange(containing: now, calendar: calendar)
            let scheduleHorizonRange = Self.scheduleHorizonRange(
                around: localDayRange,
                calendar: calendar
            )
            let profileTask = Task { try await client.fetchProfile() }
            let semestersTask = Task { try await client.fetchSemesters() }
            let hotPostsTask = Task { try await client.fetchHotPosts() }
            let localDayScheduleItemsTask = Task {
                try await client.fetchScheduleItems(
                    from: localDayRange.start,
                    to: localDayRange.end,
                    status: .all
                )
            }
            let scheduleHorizonItemsTask = Task {
                try await client.fetchScheduleItems(
                    from: scheduleHorizonRange.start,
                    to: scheduleHorizonRange.end,
                    status: .all
                )
            }

            let profile = try await profileTask.value
            let semesters = try await semestersTask.value
            let trendingPosts = try await resolveTrendingPosts(from: hotPostsTask)
            let localDayScheduleItems = try await resolveScheduleItems(from: localDayScheduleItemsTask)
            let scheduleHorizonItems = try await resolveScheduleItems(from: scheduleHorizonItemsTask)
            let scheduleItems = Self.mergeScheduleItems(
                localDayScheduleItems,
                scheduleHorizonItems
            )

            guard let semester = semesters.first else {
                state = .empty(
                    HomeEmptyContent(
                        profile: profile,
                        semesterTitle: nil,
                        state: .noSemester,
                        scheduleItems: scheduleItems,
                        lectureOptions: [],
                        trendingPosts: trendingPosts
                    )
                )
                return
            }

            let timetable = try await client.fetchTimetable(semesterId: semester.id)
            let lectureOptions = Self.makeLectureOptions(from: timetable)

            guard timetable.timetableId != nil else {
                state = .empty(
                    HomeEmptyContent(
                        profile: profile,
                        semesterTitle: semester.titleText,
                        state: .noTimetable,
                        scheduleItems: scheduleItems,
                        lectureOptions: lectureOptions,
                        trendingPosts: trendingPosts
                    )
                )
                return
            }

            let todayClasses = Self.makeTodayClassRows(
                from: timetable,
                now: now,
                calendar: calendar
            )

            guard todayClasses.isEmpty == false else {
                state = .empty(
                    HomeEmptyContent(
                        profile: profile,
                        semesterTitle: semester.titleText,
                        state: .noClassesToday,
                        scheduleItems: scheduleItems,
                        lectureOptions: lectureOptions,
                        trendingPosts: trendingPosts
                    )
                )
                return
            }

            state = .loaded(
                HomeLoadedContent(
                    profile: profile,
                    semesterTitle: semester.titleText,
                    todayClasses: todayClasses,
                    scheduleItems: scheduleItems,
                    lectureOptions: lectureOptions,
                    trendingPosts: trendingPosts
                )
            )
        } catch let error as HomeClientError {
            state = .failed(Self.map(error))
        } catch {
            state = .failed(.unexpected)
        }
    }

    private func resolveTrendingPosts(
        from task: Task<[HotPostSummary], Error>
    ) async throws -> [HotPostSummary] {
        do {
            return try await task.value
        } catch let error as HomeClientError {
            if error == .invalidSession {
                throw error
            }
            return []
        } catch {
            return []
        }
    }

    private func resolveScheduleItems(
        from task: Task<[HomeScheduleItem], Error>
    ) async throws -> [HomeScheduleItem] {
        do {
            return Self.sortScheduleItems(try await task.value)
        } catch let error as HomeClientError {
            if error == .invalidSession {
                throw error
            }
            return []
        } catch {
            return []
        }
    }

    static func localDayRange(containing date: Date, calendar: Calendar) -> DateInterval {
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        return DateInterval(start: start, end: end)
    }

    static func scheduleHorizonRange(
        around localDayRange: DateInterval,
        calendar: Calendar
    ) -> DateInterval {
        // Keep Home useful for overdue and upcoming work without issuing an unbounded database query.
        let start = calendar.date(byAdding: .year, value: -1, to: localDayRange.start)
            ?? localDayRange.start
        let end = calendar.date(byAdding: .year, value: 5, to: localDayRange.end)
            ?? localDayRange.end
        return DateInterval(start: start, end: end)
    }

    static func scheduleDateSelectionRange(
        now: Date,
        calendar: Calendar
    ) -> ClosedRange<Date> {
        let localDayRange = localDayRange(containing: now, calendar: calendar)
        let horizon = scheduleHorizonRange(around: localDayRange, calendar: calendar)
        let exclusiveEnd = horizon.end.timeIntervalSinceReferenceDate
        let inclusiveEnd = Date(timeIntervalSinceReferenceDate: exclusiveEnd.nextDown)
        let upperBound = max(horizon.start, inclusiveEnd)
        return horizon.start...upperBound
    }

    static func clamp(_ date: Date, to range: ClosedRange<Date>) -> Date {
        min(max(date, range.lowerBound), range.upperBound)
    }

    static func todayScheduleItems(
        from items: [HomeScheduleItem],
        now: Date,
        calendar: Calendar
    ) -> [HomeScheduleItem] {
        let range = localDayRange(containing: now, calendar: calendar)
        return sortScheduleItems(items.filter { item in
            guard let dueAt = item.dueAt else { return false }
            return range.start <= dueAt && dueAt < range.end
        })
    }

    static func openScheduleItems(
        from items: [HomeScheduleItem],
        todayItemIDs: Set<Int64>
    ) -> [HomeScheduleItem] {
        sortScheduleItems(items.filter { item in
            item.completed == false && todayItemIDs.contains(item.itemId) == false
        })
    }

    static func completedScheduleItems(
        from items: [HomeScheduleItem],
        todayItemIDs: Set<Int64>
    ) -> [HomeScheduleItem] {
        sortScheduleItems(items.filter { item in
            item.completed && todayItemIDs.contains(item.itemId) == false
        })
    }

    static func makeLectureOptions(from timetable: HomeTimetable) -> [HomeScheduleLectureOption] {
        timetable.lectures
            .map { HomeScheduleLectureOption(id: $0.id, name: $0.name) }
            .sorted { lhs, rhs in
                if lhs.name == rhs.name {
                    return lhs.id < rhs.id
                }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }

    static func weekdayKey(for date: Date, calendar: Calendar) -> String {
        switch calendar.component(.weekday, from: date) {
        case 1: "SUNDAY"
        case 2: "MONDAY"
        case 3: "TUESDAY"
        case 4: "WEDNESDAY"
        case 5: "THURSDAY"
        case 6: "FRIDAY"
        default: "SATURDAY"
        }
    }

    static func makeTodayClassRows(
        from timetable: HomeTimetable,
        now: Date,
        calendar: Calendar
    ) -> [TodayClassRow] {
        let weekday = weekdayKey(for: now, calendar: calendar)

        let rows = timetable.lectures.flatMap { lecture in
            lecture.schedules.compactMap { schedule -> TodayClassRow? in
                guard schedule.dayOfWeek == weekday else { return nil }
                return TodayClassRow(
                    id: "\(lecture.id)-\(schedule.dayOfWeek)-\(schedule.startTime)",
                    lectureCode: lecture.code,
                    title: lecture.name,
                    professor: lecture.professor,
                    location: schedule.location,
                    startTime: schedule.startTime,
                    endTime: schedule.endTime,
                    badge: nil
                )
            }
        }
        .sorted { lhs, rhs in
            lhs.startTime < rhs.startTime
        }

        guard rows.isEmpty == false else { return [] }

        let currentMinutes = minutes(from: now, calendar: calendar)
        let nowIndex = rows.firstIndex { row in
            guard let start = minutes(from: row.startTime),
                  let end = minutes(from: row.endTime) else {
                return false
            }
            return start <= currentMinutes && currentMinutes < end
        }

        let nextIndex: Int? = {
            if let nowIndex {
                return rows.indices.dropFirst(nowIndex + 1).first
            }
            return rows.firstIndex { row in
                guard let start = minutes(from: row.startTime) else {
                    return false
                }
                return start > currentMinutes
            }
        }()

        return rows.enumerated().map { index, row in
            let badge: TodayClassBadge?
            if nowIndex == index {
                badge = .now
            } else if nextIndex == index {
                badge = .next
            } else {
                badge = nil
            }

            return TodayClassRow(
                id: row.id,
                lectureCode: row.lectureCode,
                title: row.title,
                professor: row.professor,
                location: row.location,
                startTime: row.startTime,
                endTime: row.endTime,
                badge: badge
            )
        }
    }

    static func minutes(from time: String) -> Int? {
        let parts = time.split(separator: ":")
        guard parts.count == 2,
              let hour = Int(parts[0]),
              let minute = Int(parts[1]) else {
            return nil
        }
        return hour * 60 + minute
    }

    private static func sortScheduleItems(_ items: [HomeScheduleItem]) -> [HomeScheduleItem] {
        items.sorted { lhs, rhs in
            switch (lhs.dueAt, rhs.dueAt) {
            case let (left?, right?):
                if left == right {
                    return lhs.createdAt > rhs.createdAt
                }
                return left < right
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            case (.none, .none):
                return lhs.createdAt > rhs.createdAt
            }
        }
    }

    private static func mergeScheduleItems(_ itemGroups: [HomeScheduleItem]...) -> [HomeScheduleItem] {
        var itemsByID: [Int64: HomeScheduleItem] = [:]
        for items in itemGroups {
            for item in items where itemsByID[item.itemId] == nil {
                itemsByID[item.itemId] = item
            }
        }
        return sortScheduleItems(Array(itemsByID.values))
    }

    private func performScheduleMutation(
        _ operation: () async throws -> Void
    ) async -> Bool {
        scheduleMutationMessage = nil
        do {
            try await operation()
            return true
        } catch let error as HomeClientError {
            if error == .invalidSession {
                state = .failed(.invalidSession)
            } else {
                scheduleMutationMessage = "We couldn't save that item. Please try again."
            }
            return false
        } catch {
            scheduleMutationMessage = "We couldn't save that item. Please try again."
            return false
        }
    }

    private func replaceScheduleItem(_ item: HomeScheduleItem) {
        mutateScheduleItems { items in
            if let index = items.firstIndex(where: { $0.itemId == item.itemId }) {
                items[index] = item
            } else {
                items.append(item)
            }
            items = Self.sortScheduleItems(items)
        }
    }

    private func mutateScheduleItems(_ mutation: (inout [HomeScheduleItem]) -> Void) {
        switch state {
        case let .loaded(content):
            var scheduleItems = content.scheduleItems
            mutation(&scheduleItems)
            state = .loaded(
                HomeLoadedContent(
                    profile: content.profile,
                    semesterTitle: content.semesterTitle,
                    todayClasses: content.todayClasses,
                    scheduleItems: scheduleItems,
                    lectureOptions: content.lectureOptions,
                    trendingPosts: content.trendingPosts
                )
            )
        case let .empty(content):
            var scheduleItems = content.scheduleItems
            mutation(&scheduleItems)
            state = .empty(
                HomeEmptyContent(
                    profile: content.profile,
                    semesterTitle: content.semesterTitle,
                    state: content.state,
                    scheduleItems: scheduleItems,
                    lectureOptions: content.lectureOptions,
                    trendingPosts: content.trendingPosts
                )
            )
        default:
            return
        }
    }

    private static func minutes(from date: Date, calendar: Calendar) -> Int {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }

    private static func map(_ error: HomeClientError) -> HomeFailure {
        switch error {
        case .invalidSession:
            return .invalidSession
        case .network:
            return .network
        case .unexpected:
            return .unexpected
        }
    }
}
