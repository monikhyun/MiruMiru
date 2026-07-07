import Foundation

struct HomeMemberProfile: Equatable, Sendable {
    let memberId: Int64
    let email: String
    let nickname: String
    let universityName: String
    let universityEmailDomain: String
    let majorCode: String
    let majorName: String

    var displayName: String {
        nickname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? nickname
            : email
    }

    var secondaryText: String {
        "\(majorName) at \(universityName)"
    }

    var avatarInitials: String {
        let trimmedNickname = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedNickname.isEmpty == false {
            let words = trimmedNickname
                .split(whereSeparator: \.isWhitespace)
                .prefix(2)
            let initials = words.compactMap { $0.first }.map { String($0).uppercased() }.joined()
            if initials.isEmpty == false {
                return initials
            }
            if let first = trimmedNickname.first {
                return String(first).uppercased()
            }
        }

        if let first = email.first {
            return String(first).uppercased()
        }

        return "M"
    }
}

struct HomeSemester: Equatable, Sendable {
    let id: Int64
    let academicYear: Int
    let term: String

    var titleText: String {
        "\(academicYear) \(term.capitalized)"
    }
}

struct HomeLectureSchedule: Equatable, Sendable {
    let dayOfWeek: String
    let startTime: String
    let endTime: String
    let location: String
}

struct HomeLecture: Equatable, Sendable {
    let id: Int64
    let code: String
    let name: String
    let professor: String
    let schedules: [HomeLectureSchedule]
}

struct HomeTimetable: Equatable, Sendable {
    let timetableId: Int64?
    let semester: HomeSemester
    let lectures: [HomeLecture]
}

enum TodayClassBadge: String, Equatable, Sendable {
    case now = "NOW"
    case next = "NEXT"
}

struct TodayClassRow: Equatable, Identifiable, Sendable {
    let id: String
    let lectureCode: String
    let title: String
    let professor: String
    let location: String
    let startTime: String
    let endTime: String
    let badge: TodayClassBadge?
}

enum HomeScheduleItemType: String, CaseIterable, Codable, Equatable, Sendable {
    case quiz = "QUIZ"
    case miniTest = "MINI_TEST"
    case assignment = "ASSIGNMENT"
    case memo = "MEMO"

    var displayName: String {
        switch self {
        case .quiz:
            return "Quiz"
        case .miniTest:
            return "Mini Test"
        case .assignment:
            return "Assignment"
        case .memo:
            return "Memo"
        }
    }

    var systemImage: String {
        switch self {
        case .quiz:
            return "questionmark.circle.fill"
        case .miniTest:
            return "checkmark.seal.fill"
        case .assignment:
            return "doc.text.fill"
        case .memo:
            return "note.text"
        }
    }
}

enum HomeScheduleItemStatus: String, Equatable, Sendable {
    case all
    case open
    case completed
}

struct HomeScheduleItem: Equatable, Identifiable, Sendable {
    let itemId: Int64
    let lectureId: Int64?
    let lectureName: String?
    let type: HomeScheduleItemType
    let title: String
    let memo: String?
    let dueAt: Date?
    let completed: Bool
    let createdAt: Date
    let updatedAt: Date

    var id: Int64 { itemId }
}

struct HomeScheduleItemInput: Equatable, Sendable {
    let lectureId: Int64?
    let type: HomeScheduleItemType
    let title: String
    let memo: String?
    let dueAt: Date?
    let completed: Bool
}

struct HomeScheduleLectureOption: Equatable, Identifiable, Sendable {
    let id: Int64
    let name: String
}

enum HomeEmptyState: Equatable {
    case noSemester
    case noTimetable
    case noClassesToday

    var title: String {
        switch self {
        case .noSemester:
            return "No semester found"
        case .noTimetable:
            return "No timetable yet"
        case .noClassesToday:
            return "No classes today"
        }
    }

    var message: String {
        switch self {
        case .noSemester:
            return "We couldn't find an available semester for your account."
        case .noTimetable:
            return "Your timetable hasn't been created for the selected semester yet."
        case .noClassesToday:
            return "You're all clear for today. Check back tomorrow for your next class."
        }
    }
}

struct HomeLoadedContent: Equatable {
    let profile: HomeMemberProfile
    let semesterTitle: String
    let todayClasses: [TodayClassRow]
    let scheduleItems: [HomeScheduleItem]
    let lectureOptions: [HomeScheduleLectureOption]
    let trendingPosts: [HotPostSummary]
}

struct HomeEmptyContent: Equatable {
    let profile: HomeMemberProfile
    let semesterTitle: String?
    let state: HomeEmptyState
    let scheduleItems: [HomeScheduleItem]
    let lectureOptions: [HomeScheduleLectureOption]
    let trendingPosts: [HotPostSummary]
}

enum HomeFailure: Error, Equatable {
    case invalidSession
    case network
    case unexpected

    var message: String {
        switch self {
        case .invalidSession:
            return "Your session expired. Please log in again."
        case .network:
            return "Unable to load your home data right now."
        case .unexpected:
            return "Something went wrong while loading your home."
        }
    }
}

enum HomeViewState: Equatable {
    case loading
    case loaded(HomeLoadedContent)
    case empty(HomeEmptyContent)
    case failed(HomeFailure)
}

enum HomeClientError: Error, Equatable {
    case invalidSession
    case network
    case unexpected
}

protocol HomeClientProtocol: Sendable {
    func fetchProfile() async throws -> HomeMemberProfile
    func fetchSemesters() async throws -> [HomeSemester]
    func fetchTimetable(semesterId: Int64) async throws -> HomeTimetable
    func fetchHotPosts() async throws -> [HotPostSummary]
    func fetchScheduleItems(
        from: Date,
        to: Date,
        status: HomeScheduleItemStatus
    ) async throws -> [HomeScheduleItem]
    func createScheduleItem(_ input: HomeScheduleItemInput) async throws -> HomeScheduleItem
    func updateScheduleItem(itemId: Int64, input: HomeScheduleItemInput) async throws -> HomeScheduleItem
    func setScheduleItemCompletion(itemId: Int64, completed: Bool) async throws -> HomeScheduleItem
    func deleteScheduleItem(itemId: Int64) async throws
    func invalidateCache() async
}

extension HomeClientProtocol {
    func fetchScheduleItems(
        from: Date,
        to: Date,
        status: HomeScheduleItemStatus
    ) async throws -> [HomeScheduleItem] {
        []
    }

    func createScheduleItem(_ input: HomeScheduleItemInput) async throws -> HomeScheduleItem {
        throw HomeClientError.unexpected
    }

    func updateScheduleItem(itemId: Int64, input: HomeScheduleItemInput) async throws -> HomeScheduleItem {
        throw HomeClientError.unexpected
    }

    func setScheduleItemCompletion(itemId: Int64, completed: Bool) async throws -> HomeScheduleItem {
        throw HomeClientError.unexpected
    }

    func deleteScheduleItem(itemId: Int64) async throws {
        throw HomeClientError.unexpected
    }

    func invalidateCache() async {}
}
