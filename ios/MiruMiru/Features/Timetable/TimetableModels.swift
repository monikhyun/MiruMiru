import Foundation

struct TimetableMemberContext: Equatable, Sendable {
    let memberId: Int64
    let nickname: String
    let email: String
    let majorCode: String
    let majorName: String
}

struct TimetableSemester: Identifiable, Equatable, Sendable {
    let id: Int64
    let academicYear: Int
    let term: String

    var titleText: String {
        "\(academicYear) \(term.capitalized) Semester"
    }
}

struct TimetableMajorSummary: Equatable, Sendable {
    let majorId: Int64
    let code: String
    let name: String
}

struct TimetableLectureSchedule: Equatable, Sendable {
    let dayOfWeek: String
    let startTime: String
    let endTime: String
    let location: String
}

struct TimetableLectureItem: Identifiable, Equatable, Sendable {
    let id: Int64
    let code: String
    let name: String
    let professor: String
    let credit: Int
    let major: TimetableMajorSummary?
    let schedules: [TimetableLectureSchedule]

    var primaryLocation: String {
        orderedSchedules.first?.location ?? "TBA"
    }

    var orderedSchedules: [TimetableLectureSchedule] {
        schedules.sorted {
            let lhsDay = Self.weekdayOrder[$0.dayOfWeek.uppercased()] ?? .max
            let rhsDay = Self.weekdayOrder[$1.dayOfWeek.uppercased()] ?? .max
            if lhsDay == rhsDay {
                return $0.startTime < $1.startTime
            }
            return lhsDay < rhsDay
        }
    }

    var categoryTitle: String {
        major?.name ?? "General"
    }

    var locationSummary: String {
        let locations = orderedSchedules.map(\.location)
        let uniqueLocations = locations.reduce(into: [String]()) { result, location in
            guard result.contains(location) == false else { return }
            result.append(location)
        }

        if uniqueLocations.isEmpty {
            return "Location to be announced"
        }

        return uniqueLocations.joined(separator: " • ")
    }

    var scheduleSummary: String {
        orderedSchedules
            .map { schedule in
                "\(Self.weekdayShortTitle(schedule.dayOfWeek)) \(schedule.startTime)-\(schedule.endTime)"
            }
            .joined(separator: " • ")
    }

    private static let weekdayOrder: [String: Int] = [
        "MONDAY": 0,
        "TUESDAY": 1,
        "WEDNESDAY": 2,
        "THURSDAY": 3,
        "FRIDAY": 4
    ]

    private static func weekdayShortTitle(_ dayOfWeek: String) -> String {
        switch dayOfWeek.uppercased() {
        case "MONDAY":
            return "Mon"
        case "TUESDAY":
            return "Tue"
        case "WEDNESDAY":
            return "Wed"
        case "THURSDAY":
            return "Thu"
        case "FRIDAY":
            return "Fri"
        default:
            return dayOfWeek.prefix(3).capitalized
        }
    }
}

struct TimetableDetail: Equatable, Sendable {
    let timetableId: Int64?
    let semester: TimetableSemester
    let lectures: [TimetableLectureItem]
}

enum TimetableCatalogFilter: Hashable, Sendable {
    case all
    case memberMajor
    case general
    case major(code: String, name: String)

    var title: String {
        switch self {
        case .all:
            return "All"
        case .memberMajor:
            return "My Major"
        case .general:
            return "General"
        case let .major(_, name):
            return name
        }
    }
}

struct TimetableColorToken: Identifiable, Equatable, Sendable {
    let index: Int
    let name: String
    let hex: String

    var id: Int { index }
}

enum TimetableColorWheel {
    static let tokens: [TimetableColorToken] = [
        .init(index: 0, name: "Red", hex: "#FF0000"),
        .init(index: 1, name: "Red-Orange", hex: "#FF4500"),
        .init(index: 2, name: "Orange", hex: "#FFA500"),
        .init(index: 3, name: "Amber", hex: "#FFBF00"),
        .init(index: 4, name: "Yellow", hex: "#FFFF00"),
        .init(index: 5, name: "Yellow-Green", hex: "#7FFF00"),
        .init(index: 6, name: "Green", hex: "#008000"),
        .init(index: 7, name: "Blue-Green", hex: "#008080"),
        .init(index: 8, name: "Blue", hex: "#0000FF"),
        .init(index: 9, name: "Indigo", hex: "#4B0082"),
        .init(index: 10, name: "Violet/Purple", hex: "#800080"),
        .init(index: 11, name: "Magenta", hex: "#FF00FF")
    ]

    static var count: Int { tokens.count }

    static func token(for index: Int) -> TimetableColorToken {
        tokens[normalizedIndex(index)]
    }

    static func normalizedIndex(_ index: Int) -> Int {
        ((index % count) + count) % count
    }
}

struct TimetableHourRange: Equatable, Sendable {
    let startHour: Int
    let endHour: Int

    var hours: [Int] {
        Array(startHour..<endHour)
    }
}

struct TimetableGridBlock: Identifiable, Equatable, Sendable {
    let id: String
    let lectureId: Int64
    let title: String
    let professor: String
    let location: String
    let dayIndex: Int
    let startMinutes: Int
    let endMinutes: Int
    let accentIndex: Int
}

struct TimetableGridMarker: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let startMinutes: Int
    let endMinutes: Int
}

struct TimetableColorPickerOption: Identifiable, Equatable, Sendable {
    let token: TimetableColorToken
    let isSelected: Bool
    let isDisabled: Bool

    var id: Int { token.index }
}

enum TimetableEmptyState: Equatable {
    case noSemesters
    case noLectures

    var title: String {
        switch self {
        case .noSemesters:
            return "No semester found"
        case .noLectures:
            return "No courses in your timetable yet"
        }
    }

    var message: String {
        switch self {
        case .noSemesters:
            return "We couldn't find any available semester for your account."
        case .noLectures:
            return "Start building your week by adding a course from the catalog."
        }
    }
}

enum TimetableFailure: Error, Equatable {
    case invalidSession
    case duplicateLecture
    case timeConflict
    case lectureNotFound
    case network
    case unexpected

    var message: String {
        switch self {
        case .invalidSession:
            return "Your session expired. Please log in again."
        case .duplicateLecture:
            return "This course is already in your timetable."
        case .timeConflict:
            return "This course conflicts with another class in your timetable."
        case .lectureNotFound:
            return "We couldn't find that course anymore. Please refresh and try again."
        case .network:
            return "Unable to reach the timetable service right now."
        case .unexpected:
            return "Something went wrong while updating your timetable."
        }
    }
}

enum TimetableClientError: Error, Equatable {
    case invalidSession
    case duplicateLecture
    case timeConflict
    case lectureNotFound
    case network
    case unexpected
}

struct TimetableLoadedContent: Equatable {
    let memberContext: TimetableMemberContext
    let selectedSemester: TimetableSemester
    let timetableId: Int64?
    let lectures: [TimetableLectureItem]
    let blocks: [TimetableGridBlock]
    let markers: [TimetableGridMarker]
    let addedLectureIds: Set<Int64>
    let hourRange: TimetableHourRange
}

struct TimetableEmptyContent: Equatable {
    let memberContext: TimetableMemberContext?
    let selectedSemester: TimetableSemester?
    let hourRange: TimetableHourRange
    let markers: [TimetableGridMarker]
    let state: TimetableEmptyState
}

enum TimetableScreenState: Equatable {
    case loading
    case loaded(TimetableLoadedContent)
    case empty(TimetableEmptyContent)
    case failed(TimetableFailure)
}

enum TimetableCatalogState: Equatable {
    case idle
    case loading
    case loaded([TimetableLectureItem])
    case failed(TimetableFailure)
}

protocol TimetableClientProtocol: Sendable {
    func fetchMemberContext() async throws -> TimetableMemberContext
    func fetchSemesters() async throws -> [TimetableSemester]
    func fetchLectureCatalog(semesterId: Int64) async throws -> [TimetableLectureItem]
    func fetchMyTimetable(semesterId: Int64) async throws -> TimetableDetail
    func addLecture(semesterId: Int64, lectureId: Int64) async throws
    func removeLecture(semesterId: Int64, lectureId: Int64) async throws
    func invalidateCache() async
}

extension TimetableClientProtocol {
    func invalidateCache() async {}
}
