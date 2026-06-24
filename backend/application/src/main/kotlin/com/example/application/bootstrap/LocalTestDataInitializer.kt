package com.example.application.bootstrap

import com.example.domain.board.Board
import com.example.domain.board.BoardRepository
import com.example.domain.comment.Comment
import com.example.domain.comment.CommentRepository
import com.example.domain.course.Course
import com.example.domain.course.CourseRepository
import com.example.domain.course.CourseReview
import com.example.domain.course.CourseReviewRepository
import com.example.domain.course.CourseReviewTarget
import com.example.domain.lecture.Lecture
import com.example.domain.lecture.LectureRepository
import com.example.domain.lecture.LectureSchedule
import com.example.domain.lecture.LectureScheduleRepository
import com.example.domain.major.Major
import com.example.domain.major.MajorRepository
import com.example.domain.member.Member
import com.example.domain.member.MemberRepository
import com.example.domain.post.Post
import com.example.domain.post.PostAnonymousMapping
import com.example.domain.post.PostAnonymousMappingRepository
import com.example.domain.post.PostImage
import com.example.domain.post.PostImageRepository
import com.example.domain.post.PostLike
import com.example.domain.post.PostLikeRepository
import com.example.domain.post.PostRepository
import com.example.domain.semester.Semester
import com.example.domain.semester.SemesterRepository
import com.example.domain.semester.SemesterTerm
import com.example.domain.timetable.Timetable
import com.example.domain.timetable.TimetableLecture
import com.example.domain.timetable.TimetableLectureRepository
import com.example.domain.timetable.TimetableRepository
import com.example.domain.university.University
import com.example.domain.university.UniversityRepository
import org.springframework.boot.ApplicationArguments
import org.springframework.boot.ApplicationRunner
import org.springframework.context.annotation.Profile
import org.springframework.security.crypto.password.PasswordEncoder
import org.springframework.stereotype.Component
import org.springframework.transaction.annotation.Transactional
import java.time.DayOfWeek
import java.time.LocalTime

@Component
@Profile("local")
@Transactional
class LocalTestDataInitializer(
    private val universityRepository: UniversityRepository,
    private val majorRepository: MajorRepository,
    private val memberRepository: MemberRepository,
    private val boardRepository: BoardRepository,
    private val postRepository: PostRepository,
    private val postLikeRepository: PostLikeRepository,
    private val postAnonymousMappingRepository: PostAnonymousMappingRepository,
    private val commentRepository: CommentRepository,
    private val postImageRepository: PostImageRepository,
    private val semesterRepository: SemesterRepository,
    private val courseRepository: CourseRepository,
    private val courseReviewRepository: CourseReviewRepository,
    private val courseReviewTargetService: com.example.application.course.CourseReviewTargetService,
    private val lectureRepository: LectureRepository,
    private val lectureScheduleRepository: LectureScheduleRepository,
    private val timetableRepository: TimetableRepository,
    private val timetableLectureRepository: TimetableLectureRepository,
    private val passwordEncoder: PasswordEncoder
) : ApplicationRunner {

    override fun run(args: ApplicationArguments) {
        val university = findOrCreateUniversity()
        val majorsByCode = MAJOR_SEEDS.associate { seed ->
            seed.code to findOrCreateMajor(university, seed)
        }
        val testMember = findOrCreateMember(university, majorsByCode.getValue(TEST_MEMBER_MAJOR_CODE))
        val emptyMember = findOrCreateMember(
            university,
            majorsByCode.getValue(EMPTY_MEMBER_MAJOR_CODE),
            EMPTY_MEMBER_EMAIL,
            EMPTY_MEMBER_NICKNAME
        )
        findOrCreateMember(
            university,
            majorsByCode.getValue(PARTNER_MEMBER_MAJOR_CODE),
            PARTNER_MEMBER_EMAIL,
            PARTNER_MEMBER_NICKNAME
        )
        val boardsByCode = BOARD_SEEDS.associate { seed ->
            seed.code to findOrCreateBoard(university, seed)
        }
        val semestersByKey = SEMESTER_SEEDS.associate { seed ->
            SemesterKey(seed.academicYear, seed.term) to findOrCreateSemester(university, seed)
        }
        val lectures = LECTURE_SEEDS.map { seed ->
            val semester = semestersByKey.getValue(SemesterKey(seed.academicYear, seed.term))
            val course = findOrCreateCourse(university, seed)
            findOrCreateLecture(semester, majorsByCode[seed.majorCode], course, seed)
        }
        val currentSemester = semestersByKey.getValue(SemesterKey(SEED_ACADEMIC_YEAR, SEED_TERM))

        lectures.zip(LECTURE_SEEDS).forEach { (lecture, seed) ->
            seed.schedules.forEach { schedule ->
                findOrCreateLectureSchedule(lecture, schedule)
            }
        }
        val targetsByKey = lectures.associate { lecture ->
            CourseReviewTargetKey(lecture.course.code, lecture.professor) to findOrCreateCourseReviewTarget(lecture)
        }

        val timetable = findOrCreateTimetable(testMember, currentSemester)
        lectures.filter { it.semester.id == currentSemester.id && INITIAL_TIMETABLE_LECTURE_CODES.contains(it.code) }.forEach { lecture ->
            linkLectureToTimetable(timetable, lecture)
        }

        POST_SEEDS.forEach { seed ->
            val author = when (seed.memberEmail) {
                EMPTY_MEMBER_EMAIL -> emptyMember
                else -> testMember
            }
            val board = boardsByCode.getValue(seed.boardCode)
            val post = findOrCreatePost(board, author, seed)
            seed.images.forEach { imageSeed ->
                findOrCreatePostImage(post, imageSeed)
            }
        }

        val postsByTitle = POST_SEEDS.associate { seed ->
            val board = boardsByCode.getValue(seed.boardCode)
            seed.title to (postRepository.findByBoardIdAndTitle(board.id, seed.title)
                ?: error("Seed post must exist for title=${seed.title}"))
        }

        POST_ANON_MAPPING_SEEDS.forEach { seed ->
            val post = postsByTitle.getValue(seed.postTitle)
            val mappedMember = when (seed.memberEmail) {
                EMPTY_MEMBER_EMAIL -> emptyMember
                else -> testMember
            }
            findOrCreatePostAnonymousMapping(post, mappedMember, seed.anonNumber)
        }

        POST_LIKE_SEEDS.forEach { seed ->
            val post = postsByTitle.getValue(seed.postTitle)
            val likedMember = when (seed.memberEmail) {
                EMPTY_MEMBER_EMAIL -> emptyMember
                else -> testMember
            }
            findOrCreatePostLike(post, likedMember)
        }

        COMMENT_SEEDS.forEach { seed ->
            val post = postsByTitle.getValue(seed.postTitle)
            val commentMember = when (seed.memberEmail) {
                EMPTY_MEMBER_EMAIL -> emptyMember
                else -> testMember
            }
            val parent = seed.parentContent?.let { parentContent ->
                commentRepository.findAllByPostIdOrderByCreatedAtAsc(post.id)
                    .firstOrNull { comment -> comment.content == parentContent }
                    ?: error("Parent comment must exist for content=$parentContent")
            }
            findOrCreateComment(post, commentMember, parent, seed)
        }

        COURSE_REVIEW_SEEDS.forEach { seed ->
            val member = when (seed.memberEmail) {
                EMPTY_MEMBER_EMAIL -> emptyMember
                else -> testMember
            }
            val target = targetsByKey.getValue(
                CourseReviewTargetKey(
                    courseCode = seed.courseCode,
                    professorDisplayName = seed.professorDisplayName
                )
            )
            findOrCreateCourseReview(
                target = target,
                member = member,
                seed = seed
            )
        }
    }

    private fun findOrCreateUniversity(): University {
        return universityRepository.findByEmailDomain(TOKYO_EMAIL_DOMAIN)
            ?: universityRepository.save(
                University(
                    name = TOKYO_UNIVERSITY_NAME,
                    emailDomain = TOKYO_EMAIL_DOMAIN
                )
            )
    }

    private fun findOrCreateMajor(university: University, seed: MajorSeed): Major {
        return majorRepository.findByUniversityIdAndCode(university.id, seed.code)
            ?: majorRepository.save(
                Major(
                    university = university,
                    code = seed.code,
                    name = seed.name
                )
            )
    }

    private fun findOrCreateBoard(university: University, seed: BoardSeed): Board {
        return boardRepository.findByUniversityIdAndCode(university.id, seed.code)
            ?: boardRepository.save(
                Board(
                    university = university,
                    code = seed.code,
                    name = seed.name,
                    isAnonymousAllowed = seed.isAnonymousAllowed
                )
            )
    }

    private fun findOrCreateMember(
        university: University,
        major: Major,
        email: String = TEST_MEMBER_EMAIL,
        nickname: String = TEST_MEMBER_NICKNAME
    ): Member {
        val existingMember = memberRepository.findByEmail(email)
        if (existingMember != null) {
            require(existingMember.university.id == university.id) {
                "Test member must belong to the seeded university."
            }
            require(existingMember.major.id == major.id) {
                "Test member must belong to the seeded major."
            }
            return existingMember
        }

        return memberRepository.save(
            Member(
                university = university,
                major = major,
                email = email,
                password = passwordEncoder.encode(TEST_MEMBER_PASSWORD),
                nickname = nickname,
                role = TEST_MEMBER_ROLE
            )
        )
    }

    private fun findOrCreateSemester(university: University, seed: SemesterSeed): Semester {
        return semesterRepository.findByUniversityIdAndAcademicYearAndTerm(
            universityId = university.id,
            academicYear = seed.academicYear,
            term = seed.term
        ) ?: semesterRepository.save(
            Semester(
                university = university,
                academicYear = seed.academicYear,
                term = seed.term
            )
            )
    }

    private fun findOrCreateCourse(university: University, seed: LectureSeed): Course {
        return courseRepository.findByUniversityIdAndCode(university.id, seed.courseCode)
            ?: courseRepository.save(
                Course(
                    university = university,
                    code = seed.courseCode,
                    name = seed.courseName
                )
            )
    }

    private fun findOrCreateLecture(semester: Semester, major: Major?, course: Course, seed: LectureSeed): Lecture {
        return lectureRepository.findBySemesterIdAndCode(semester.id, seed.code)
            ?: lectureRepository.save(
                Lecture(
                    semester = semester,
                    major = major,
                    course = course,
                    code = seed.code,
                    name = seed.name,
                    professor = seed.professor,
                    credit = seed.credit
                )
            )
    }

    private fun findOrCreateCourseReviewTarget(lecture: Lecture): CourseReviewTarget {
        return courseReviewTargetService.ensureTarget(lecture.course, lecture.professor)
    }

    private fun findOrCreateCourseReview(target: CourseReviewTarget, member: Member, seed: CourseReviewSeed): CourseReview {
        return courseReviewRepository.findByTargetIdAndMemberId(target.id, member.id)
            ?: courseReviewRepository.save(
                CourseReview(
                    target = target,
                    member = member,
                    academicYear = seed.academicYear,
                    term = seed.term,
                    professorDisplayName = target.professorDisplayName,
                    overallRating = seed.overallRating,
                    difficulty = seed.difficulty,
                    workload = seed.workload,
                    wouldTakeAgain = seed.wouldTakeAgain,
                    content = seed.content,
                    professorRating = seed.professorRating,
                    professorContent = seed.professorContent
                )
            )
    }

    private fun findOrCreatePost(board: Board, member: Member, seed: PostSeed): Post {
        require(board.university.id == member.university.id) {
            "Board and post author must belong to the same university."
        }
        require(board.isAnonymousAllowed || !seed.isAnonymous) {
            "Anonymous sample posts must target anonymous-enabled boards."
        }

        return postRepository.findByBoardIdAndTitle(board.id, seed.title)
            ?: postRepository.save(
                Post(
                    board = board,
                    member = member,
                    title = seed.title,
                    content = seed.content,
                    isAnonymous = seed.isAnonymous,
                    likeCount = seed.likeCount,
                    commentCount = seed.commentCount,
                    isDeleted = false
                )
            )
    }

    private fun findOrCreatePostImage(post: Post, seed: PostImageSeed): PostImage {
        return postImageRepository.findByPostIdAndDisplayOrder(post.id, seed.displayOrder)
            ?: postImageRepository.save(
                PostImage(
                    post = post,
                    imageUrl = seed.imageUrl,
                    displayOrder = seed.displayOrder
                )
            )
    }

    private fun findOrCreatePostLike(post: Post, member: Member): PostLike {
        return postLikeRepository.findByPostIdAndMemberId(post.id, member.id)
            ?: postLikeRepository.save(
                PostLike(
                    post = post,
                    member = member
                )
            )
    }

    private fun findOrCreatePostAnonymousMapping(post: Post, member: Member, anonNumber: Int): PostAnonymousMapping {
        return postAnonymousMappingRepository.findByPostIdAndMemberId(post.id, member.id)
            ?: postAnonymousMappingRepository.save(
                PostAnonymousMapping(
                    post = post,
                    member = member,
                    anonNumber = anonNumber
                )
            )
    }

    private fun findOrCreateComment(post: Post, member: Member, parent: Comment?, seed: CommentSeed): Comment {
        return commentRepository.findAllByPostIdOrderByCreatedAtAsc(post.id)
            .firstOrNull { comment ->
                comment.member.id == member.id &&
                    comment.content == seed.content &&
                    comment.parent?.id == parent?.id
            }
            ?: commentRepository.save(
                Comment(
                    post = post,
                    member = member,
                    parent = parent,
                    content = seed.content,
                    isAnonymous = seed.isAnonymous,
                    isDeleted = seed.isDeleted
                )
            )
    }

    private fun findOrCreateLectureSchedule(lecture: Lecture, seed: LectureScheduleSeed): LectureSchedule {
        return lectureScheduleRepository.findByLectureIdAndDayOfWeekAndStartTimeAndEndTime(
            lectureId = lecture.id,
            dayOfWeek = seed.dayOfWeek,
            startTime = seed.startTime,
            endTime = seed.endTime
        ) ?: lectureScheduleRepository.save(
            LectureSchedule(
                lecture = lecture,
                dayOfWeek = seed.dayOfWeek,
                startTime = seed.startTime,
                endTime = seed.endTime,
                location = seed.location
            )
        )
    }

    private fun findOrCreateTimetable(member: Member, semester: Semester): Timetable {
        require(member.university.id == semester.university.id) {
            "Timetable member and semester must belong to the same university."
        }

        return timetableRepository.findByMemberIdAndSemesterId(member.id, semester.id)
            ?: timetableRepository.save(
                Timetable(
                    member = member,
                    semester = semester
                )
            )
    }

    private fun linkLectureToTimetable(timetable: Timetable, lecture: Lecture) {
        require(timetable.semester.id == lecture.semester.id) {
            "Timetable and lecture must belong to the same semester."
        }
        require(timetable.member.university.id == lecture.semester.university.id) {
            "Timetable member and lecture must belong to the same university."
        }

        if (timetableLectureRepository.existsByTimetableIdAndLectureId(timetable.id, lecture.id)) {
            return
        }

        timetableLectureRepository.save(
            TimetableLecture(
                timetable = timetable,
                lecture = lecture
            )
        )
    }

    companion object {
        private const val TOKYO_UNIVERSITY_NAME = "The University of Tokyo"
        private const val TOKYO_EMAIL_DOMAIN = "tokyo.ac.jp"
        private const val TEST_MEMBER_EMAIL = "test@tokyo.ac.jp"
        private const val TEST_MEMBER_PASSWORD = "password123!"
        private const val TEST_MEMBER_NICKNAME = "test-user"
        private const val TEST_MEMBER_ROLE = "ROLE_USER"
        private const val TEST_MEMBER_MAJOR_CODE = "CS"
        private const val EMPTY_MEMBER_EMAIL = "empty@tokyo.ac.jp"
        private const val EMPTY_MEMBER_NICKNAME = "empty-user"
        private const val EMPTY_MEMBER_MAJOR_CODE = "MATH"
        private const val PARTNER_MEMBER_EMAIL = "partner@tokyo.ac.jp"
        private const val PARTNER_MEMBER_NICKNAME = "partner-user"
        private const val PARTNER_MEMBER_MAJOR_CODE = "CS"
        private const val SEED_ACADEMIC_YEAR = 2026
        private val SEED_TERM = SemesterTerm.SPRING
        private val INITIAL_TIMETABLE_LECTURE_CODES = setOf("CS101", "MATH201")
        private val SEMESTER_SEEDS = listOf(
            SemesterSeed(
                academicYear = 2026,
                term = SemesterTerm.SPRING
            ),
            SemesterSeed(
                academicYear = 2025,
                term = SemesterTerm.FALL
            )
        )
        private val BOARD_SEEDS = listOf(
            BoardSeed(
                code = "general",
                name = "General",
                isAnonymousAllowed = false
            ),
            BoardSeed(
                code = "free",
                name = "Free Talk",
                isAnonymousAllowed = true
            )
        )
        private val POST_SEEDS = listOf(
            PostSeed(
                boardCode = "general",
                memberEmail = TEST_MEMBER_EMAIL,
                title = "Welcome to MiruMiru",
                content = "Use this board to share campus updates and study tips.",
                isAnonymous = false,
                likeCount = 0,
                commentCount = 0,
                images = listOf(
                    PostImageSeed(
                        imageUrl = "https://example.com/images/mirumiru-welcome.png",
                        displayOrder = 0
                    )
                )
            ),
            PostSeed(
                boardCode = "free",
                memberEmail = TEST_MEMBER_EMAIL,
                title = "Best lunch near campus?",
                content = "Looking for affordable lunch spots around the engineering buildings.",
                isAnonymous = true,
                likeCount = 1,
                commentCount = 2
            )
        )
        private val POST_ANON_MAPPING_SEEDS = listOf(
            PostAnonMappingSeed(
                postTitle = "Best lunch near campus?",
                memberEmail = TEST_MEMBER_EMAIL,
                anonNumber = 1
            ),
            PostAnonMappingSeed(
                postTitle = "Best lunch near campus?",
                memberEmail = EMPTY_MEMBER_EMAIL,
                anonNumber = 2
            )
        )
        private val POST_LIKE_SEEDS = listOf(
            PostLikeSeed(
                postTitle = "Best lunch near campus?",
                memberEmail = EMPTY_MEMBER_EMAIL
            )
        )
        private val COMMENT_SEEDS = listOf(
            CommentSeed(
                postTitle = "Best lunch near campus?",
                memberEmail = EMPTY_MEMBER_EMAIL,
                content = "There is a cheap curry place behind the engineering building.",
                isAnonymous = true
            ),
            CommentSeed(
                postTitle = "Best lunch near campus?",
                memberEmail = TEST_MEMBER_EMAIL,
                parentContent = "There is a cheap curry place behind the engineering building.",
                content = "Thanks, I will try that place tomorrow.",
                isAnonymous = true
            )
        )

        private val MAJOR_SEEDS = listOf(
            MajorSeed(
                code = "CS",
                name = "Computer Science"
            ),
            MajorSeed(
                code = "MATH",
                name = "Mathematics"
            )
        )

        private val LECTURE_SEEDS = listOf(
            LectureSeed(
                academicYear = 2026,
                term = SemesterTerm.SPRING,
                code = "CS101",
                courseCode = "CS101",
                courseName = "Introduction to Computer Science",
                name = "Introduction to Computer Science",
                professor = "Prof. Akiyama",
                credit = 3,
                majorCode = "CS",
                schedules = listOf(
                    LectureScheduleSeed(
                        dayOfWeek = DayOfWeek.MONDAY,
                        startTime = LocalTime.of(9, 0),
                        endTime = LocalTime.of(10, 30),
                        location = "Engineering Hall 101"
                    ),
                    LectureScheduleSeed(
                        dayOfWeek = DayOfWeek.WEDNESDAY,
                        startTime = LocalTime.of(9, 0),
                        endTime = LocalTime.of(10, 30),
                        location = "Engineering Hall 101"
                    )
                )
            ),
            LectureSeed(
                academicYear = 2026,
                term = SemesterTerm.SPRING,
                code = "MATH201",
                courseCode = "MATH201",
                courseName = "Linear Algebra",
                name = "Linear Algebra",
                professor = "Prof. Sato",
                credit = 2,
                majorCode = null,
                schedules = listOf(
                    LectureScheduleSeed(
                        dayOfWeek = DayOfWeek.TUESDAY,
                        startTime = LocalTime.of(13, 0),
                        endTime = LocalTime.of(14, 30),
                        location = "Science Building 202"
                    )
                )
            ),
            LectureSeed(
                academicYear = 2026,
                term = SemesterTerm.SPRING,
                code = "PHYS301",
                courseCode = "PHYS301",
                courseName = "Classical Mechanics",
                name = "Classical Mechanics",
                professor = "Prof. Tanaka",
                credit = 3,
                majorCode = null,
                schedules = listOf(
                    LectureScheduleSeed(
                        dayOfWeek = DayOfWeek.MONDAY,
                        startTime = LocalTime.of(10, 0),
                        endTime = LocalTime.of(11, 0),
                        location = "Physics Hall 303"
                    )
                )
            ),
            LectureSeed(
                academicYear = 2026,
                term = SemesterTerm.SPRING,
                code = "HIST110",
                courseCode = "HIST110",
                courseName = "World History",
                name = "World History",
                professor = "Prof. Nakamura",
                credit = 2,
                majorCode = null,
                schedules = listOf(
                    LectureScheduleSeed(
                        dayOfWeek = DayOfWeek.TUESDAY,
                        startTime = LocalTime.of(9, 0),
                        endTime = LocalTime.of(10, 30),
                        location = "Humanities Hall 105"
                    )
                )
            ),
            LectureSeed(
                academicYear = 2026,
                term = SemesterTerm.SPRING,
                code = "CHEM105",
                courseCode = "CHEM105",
                courseName = "General Chemistry",
                name = "General Chemistry",
                professor = "Prof. Suzuki",
                credit = 3,
                majorCode = null,
                schedules = listOf(
                    LectureScheduleSeed(
                        dayOfWeek = DayOfWeek.WEDNESDAY,
                        startTime = LocalTime.of(14, 0),
                        endTime = LocalTime.of(15, 30),
                        location = "Science Building 110"
                    )
                )
            ),
            LectureSeed(
                academicYear = 2026,
                term = SemesterTerm.SPRING,
                code = "ECON210",
                courseCode = "ECON210",
                courseName = "Microeconomics",
                name = "Microeconomics",
                professor = "Prof. Kobayashi",
                credit = 2,
                majorCode = null,
                schedules = listOf(
                    LectureScheduleSeed(
                        dayOfWeek = DayOfWeek.THURSDAY,
                        startTime = LocalTime.of(10, 0),
                        endTime = LocalTime.of(11, 30),
                        location = "Social Sciences 204"
                    )
                )
            ),
            LectureSeed(
                academicYear = 2026,
                term = SemesterTerm.SPRING,
                code = "ENG220",
                courseCode = "ENG220",
                courseName = "Academic English",
                name = "Academic English",
                professor = "Prof. Wilson",
                credit = 2,
                majorCode = null,
                schedules = listOf(
                    LectureScheduleSeed(
                        dayOfWeek = DayOfWeek.THURSDAY,
                        startTime = LocalTime.of(13, 0),
                        endTime = LocalTime.of(14, 30),
                        location = "Language Center 301"
                    )
                )
            ),
            LectureSeed(
                academicYear = 2026,
                term = SemesterTerm.SPRING,
                code = "STAT230",
                courseCode = "STAT230",
                courseName = "Statistics Fundamentals",
                name = "Statistics Fundamentals",
                professor = "Prof. Yamamoto",
                credit = 2,
                majorCode = "MATH",
                schedules = listOf(
                    LectureScheduleSeed(
                        dayOfWeek = DayOfWeek.FRIDAY,
                        startTime = LocalTime.of(9, 0),
                        endTime = LocalTime.of(10, 30),
                        location = "Science Building 305"
                    )
                )
            ),
            LectureSeed(
                academicYear = 2026,
                term = SemesterTerm.SPRING,
                code = "ART150",
                courseCode = "ART150",
                courseName = "Visual Arts Appreciation",
                name = "Visual Arts Appreciation",
                professor = "Prof. Lee",
                credit = 2,
                majorCode = null,
                schedules = listOf(
                    LectureScheduleSeed(
                        dayOfWeek = DayOfWeek.FRIDAY,
                        startTime = LocalTime.of(11, 0),
                        endTime = LocalTime.of(12, 30),
                        location = "Arts Hall 201"
                    )
                )
            ),
            LectureSeed(
                academicYear = 2025,
                term = SemesterTerm.FALL,
                code = "CS101",
                courseCode = "CS101",
                courseName = "Introduction to Computer Science",
                name = "Introduction to Computer Science",
                professor = "Prof. Ito",
                credit = 3,
                majorCode = "CS",
                schedules = listOf(
                    LectureScheduleSeed(
                        dayOfWeek = DayOfWeek.TUESDAY,
                        startTime = LocalTime.of(10, 0),
                        endTime = LocalTime.of(11, 30),
                        location = "Engineering Hall 204"
                    ),
                    LectureScheduleSeed(
                        dayOfWeek = DayOfWeek.THURSDAY,
                        startTime = LocalTime.of(10, 0),
                        endTime = LocalTime.of(11, 30),
                        location = "Engineering Hall 204"
                    )
                )
            )
        )
        private val COURSE_REVIEW_SEEDS = listOf(
            CourseReviewSeed(
                memberEmail = TEST_MEMBER_EMAIL,
                courseCode = "CS101",
                professorDisplayName = "Prof. Ito",
                academicYear = 2025,
                term = SemesterTerm.FALL,
                overallRating = 10,
                professorRating = 9,
                difficulty = 3,
                workload = 2,
                wouldTakeAgain = true,
                content = "Clear explanations and manageable assignments.",
                professorContent = "Prof. Ito explains concepts clearly and gives helpful feedback."
            ),
            CourseReviewSeed(
                memberEmail = EMPTY_MEMBER_EMAIL,
                courseCode = "CS101",
                professorDisplayName = "Prof. Akiyama",
                academicYear = 2026,
                term = SemesterTerm.SPRING,
                overallRating = 8,
                professorRating = 8,
                difficulty = 4,
                workload = 3,
                wouldTakeAgain = true,
                content = "Fast-paced but still one of the better core classes.",
                professorContent = "Prof. Akiyama keeps the class moving and answers questions directly."
            )
        )
    }

    private data class SemesterSeed(
        val academicYear: Int,
        val term: SemesterTerm
    )

    private data class MajorSeed(
        val code: String,
        val name: String
    )

    private data class BoardSeed(
        val code: String,
        val name: String,
        val isAnonymousAllowed: Boolean
    )

    private data class LectureSeed(
        val academicYear: Int,
        val term: SemesterTerm,
        val code: String,
        val courseCode: String,
        val courseName: String,
        val name: String,
        val professor: String,
        val credit: Int,
        val majorCode: String?,
        val schedules: List<LectureScheduleSeed>
    )

    private data class PostSeed(
        val boardCode: String,
        val memberEmail: String,
        val title: String,
        val content: String,
        val isAnonymous: Boolean,
        val likeCount: Int,
        val commentCount: Int,
        val images: List<PostImageSeed> = emptyList()
    )

    private data class PostAnonMappingSeed(
        val postTitle: String,
        val memberEmail: String,
        val anonNumber: Int
    )

    private data class PostLikeSeed(
        val postTitle: String,
        val memberEmail: String
    )

    private data class CommentSeed(
        val postTitle: String,
        val memberEmail: String,
        val content: String,
        val isAnonymous: Boolean,
        val isDeleted: Boolean = false,
        val parentContent: String? = null
    )

    private data class PostImageSeed(
        val imageUrl: String,
        val displayOrder: Int
    )

    private data class LectureScheduleSeed(
        val dayOfWeek: DayOfWeek,
        val startTime: LocalTime,
        val endTime: LocalTime,
        val location: String
    )

    private data class CourseReviewSeed(
        val memberEmail: String,
        val courseCode: String,
        val professorDisplayName: String,
        val academicYear: Int,
        val term: SemesterTerm,
        val overallRating: Int,
        val professorRating: Int,
        val difficulty: Int,
        val workload: Int,
        val wouldTakeAgain: Boolean,
        val content: String,
        val professorContent: String?
    )

    private data class SemesterKey(
        val academicYear: Int,
        val term: SemesterTerm
    )

    private data class LectureSeedKey(
        val academicYear: Int,
        val term: SemesterTerm,
        val code: String
    )

    private data class CourseReviewTargetKey(
        val courseCode: String,
        val professorDisplayName: String
    )
}
