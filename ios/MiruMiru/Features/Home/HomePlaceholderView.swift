import SwiftUI

struct HomeView: View {
    @ObservedObject private var session: AppSession
    @ObservedObject private var boardsSyncStore: BoardsSyncStore
    @StateObject private var viewModel: HomeViewModel
    private let isActive: Bool
    private let onSemesterTap: () -> Void
    private let onBoardsTap: () -> Void
    private let onTrendingPostTap: (Int64) -> Void
    @State private var showLogoutPrompt = false
    @State private var scheduleEditor: HomeScheduleEditorDestination?

    init(
        session: AppSession,
        client: HomeClientProtocol,
        boardsSyncStore: BoardsSyncStore,
        isActive: Bool = true,
        onSemesterTap: @escaping () -> Void = {},
        onBoardsTap: @escaping () -> Void = {},
        onTrendingPostTap: @escaping (Int64) -> Void = { _ in },
        nowProvider: @escaping @Sendable () -> Date = Date.init,
        calendar: Calendar = .current
    ) {
        self.session = session
        self.boardsSyncStore = boardsSyncStore
        self.isActive = isActive
        self.onSemesterTap = onSemesterTap
        self.onBoardsTap = onBoardsTap
        self.onTrendingPostTap = onTrendingPostTap
        _viewModel = StateObject(
            wrappedValue: HomeViewModel(
                client: client,
                nowProvider: nowProvider,
                calendar: calendar
            )
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 28) {
                switch viewModel.state {
                case .loading:
                    loadingHeader
                        HomeLoadingCard()
                case let .loaded(content):
                    let trendingPosts = boardsSyncStore.projectHotPosts(content.trendingPosts)
                    HomeHeaderSection(
                        profile: content.profile,
                        onLogoutTap: { showLogoutPrompt = true }
                    )
                    TodayClassesSection(
                        semesterTitle: content.semesterTitle,
                        rows: content.todayClasses,
                        onSemesterTap: onSemesterTap
                    )
                    scheduleSection
                    if trendingPosts.isEmpty == false {
                        HomeTrendingPostsSection(
                            posts: trendingPosts,
                            onBoardsTap: onBoardsTap,
                            onPostTap: onTrendingPostTap
                        )
                    }
                case let .empty(content):
                    let trendingPosts = boardsSyncStore.projectHotPosts(content.trendingPosts)
                    HomeHeaderSection(
                        profile: content.profile,
                        onLogoutTap: { showLogoutPrompt = true }
                    )
                    HomeEmptyCard(
                        title: content.state.title,
                        message: content.state.message,
                        semesterTitle: content.semesterTitle,
                        onSemesterTap: onSemesterTap
                    )
                    scheduleSection
                    if trendingPosts.isEmpty == false {
                        HomeTrendingPostsSection(
                            posts: trendingPosts,
                            onBoardsTap: onBoardsTap,
                            onPostTap: onTrendingPostTap
                        )
                    }
                case let .failed(failure):
                    failureCard(failure)
                }
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, AuthenticatedLayoutMetrics.rootContentBottomSpacing)
            }
            .background(background)
            .task(id: isActive) {
                guard isActive else { return }
                await viewModel.loadForActivation()
            }
            .onChange(of: viewModel.state) { _, _ in
                guard viewModel.invalidateStateIfNeeded() else { return }
                session.invalidateSession()
            }
            .onChange(of: viewModel.hotPostsSnapshotForSync()) { _, hotPosts in
                if let hotPosts {
                    boardsSyncStore.ingestHotPosts(hotPosts)
                }
            }
            .confirmationDialog(
                "Log out of MiruMiru?",
                isPresented: $showLogoutPrompt,
                titleVisibility: .visible
            ) {
                Button("Log Out", role: .destructive) {
                    session.logoutToLogin()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("You'll need to sign in again to access your campus features.")
            }
            .sheet(item: $scheduleEditor) { destination in
                HomeScheduleEditorView(
                    viewModel: viewModel,
                    destination: destination,
                    lectureOptions: viewModel.lectureOptionsSnapshot()
                )
            }
        }
    }

    private var scheduleSection: some View {
        HomeScheduleSection(
            todayDeadlines: viewModel.todayDeadlinesSnapshot(),
            openTasks: viewModel.openScheduleItemsSnapshot(),
            completedTasks: viewModel.completedScheduleItemsSnapshot(),
            mutationMessage: viewModel.scheduleMutationMessage,
            onQuickAdd: { type in
                scheduleEditor = .create(type)
            },
            onToggleCompletion: { item in
                Task {
                    await viewModel.toggleScheduleItemCompletion(item)
                }
            },
            onEdit: { item in
                scheduleEditor = .edit(item)
            },
            onDelete: { item in
                Task {
                    await viewModel.deleteScheduleItem(item)
                }
            },
            onDismissMessage: viewModel.clearScheduleMutationMessage
        )
    }

    private var background: some View {
        AppTheme.pageBackground.ignoresSafeArea()
    }

    private var loadingHeader: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 14) {
                Circle()
                    .fill(AppTheme.surfaceSecondary)
                    .frame(width: 58, height: 58)

                VStack(alignment: .leading, spacing: 8) {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(AppTheme.surfaceSecondary)
                        .frame(width: 60, height: 14)

                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(AppTheme.divider)
                        .frame(width: 180, height: 22)
                }

                Spacer()

                Image(systemName: "bell.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(AppTheme.textSecondary)
            }

            ProgressView("Loading your home...")
                .font(AppFont.medium(15, relativeTo: .subheadline))
                .tint(AuthPalette.primaryStart)
        }
    }

    private func failureCard(_ failure: HomeFailure) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Home")
                .font(AppFont.extraBold(32, relativeTo: .largeTitle))
                .foregroundStyle(AppTheme.textPrimary)

            VStack(alignment: .leading, spacing: 12) {
                Text("We couldn't load your home")
                    .font(AppFont.bold(22, relativeTo: .title3))
                    .foregroundStyle(AppTheme.textPrimary)

                Text(failure.message)
                    .font(AppFont.medium(16, relativeTo: .body))
                    .foregroundStyle(AppTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                PrimaryActionButton(
                    title: "Try Again",
                    isLoading: false,
                    isDisabled: false,
                    height: 64,
                    cornerRadius: 20
                ) {
                    Task {
                        await viewModel.reload()
                    }
                }
            }
            .padding(22)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(AppTheme.surfacePrimary)
                    .shadow(color: Color.black.opacity(0.05), radius: 16, y: 8)
            )
        }
        .padding(.top, 12)
    }
}

private struct HomeHeaderSection: View {
    let profile: HomeMemberProfile
    let onLogoutTap: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            HomeAvatar(initials: profile.avatarInitials)

            VStack(alignment: .leading, spacing: 3) {
                Text("Hello,")
                    .font(AppFont.medium(17, relativeTo: .body))
                    .foregroundStyle(AppTheme.textSecondary)

                Text(profile.displayName)
                    .font(AppFont.extraBold(30, relativeTo: .largeTitle))
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)

                Text(profile.secondaryText)
                    .font(AppFont.medium(15, relativeTo: .subheadline))
                    .foregroundStyle(AppTheme.textSecondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 16)

            Button(action: onLogoutTap) {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(AppTheme.textSecondary)
                    .frame(width: 42, height: 42)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Log out")
        }
    }
}

private struct HomeAvatar: View {
    let initials: String

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Circle()
                .stroke(AuthPalette.primaryStart, lineWidth: 2)
                .background {
                    Circle()
                        .fill(Color(red: 0.98, green: 0.90, blue: 0.82))
                        .padding(5)
                        .overlay {
                            Text(initials)
                                .font(AppFont.bold(18, relativeTo: .headline))
                                .foregroundStyle(AppTheme.textPrimary)
                        }
                }
                .frame(width: 58, height: 58)

            Circle()
                .fill(Color(red: 0.29, green: 0.84, blue: 0.46))
                .frame(width: 11, height: 11)
                .overlay {
                    Circle()
                        .stroke(Color.white, lineWidth: 2)
                }
                .offset(x: 2, y: 2)
        }
    }
}

private struct TodayClassesSection: View {
    let semesterTitle: String
    let rows: [TodayClassRow]
    let onSemesterTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Today's Classes")
                    .font(AppFont.extraBold(28, relativeTo: .title2))
                    .foregroundStyle(AppTheme.textPrimary)

                Spacer()

                Button(action: onSemesterTap) {
                    Text(semesterTitle)
                        .font(AppFont.semibold(15, relativeTo: .subheadline))
                        .foregroundStyle(AuthPalette.primaryStart)
                }
                .buttonStyle(.plain)
            }

            VStack(spacing: 18) {
                ForEach(rows) { row in
                    HomeClassCard(row: row)
                }
            }
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .fill(AppTheme.surfaceSecondary)
            )
        }
    }
}

private struct HomeClassCard: View {
    let row: TodayClassRow
    @State private var cardHeight: CGFloat = Self.minimumCardHeight

    private static let minimumCardHeight: CGFloat = 122

    private var accentColor: Color {
        switch row.badge {
        case .now:
            return AuthPalette.primaryStart
        case .next:
            return Color(red: 0.71, green: 0.78, blue: 0.90)
        case nil:
            return Color(red: 0.82, green: 0.87, blue: 0.95)
        }
    }

    var body: some View {
        let cardShape = RoundedRectangle(cornerRadius: 26, style: .continuous)

        HStack(alignment: .top, spacing: 18) {
            ZStack {
                Rectangle()
                    .fill(AppTheme.divider)
                    .frame(width: 2, height: max(cardHeight - 58, 26))

                VStack(spacing: 0) {
                    Text(row.startTime)
                        .font(AppFont.bold(23, relativeTo: .title3))
                        .foregroundStyle(AuthPalette.primaryStart)
                        .monospacedDigit()
                        .lineLimit(1)

                    Spacer(minLength: 0)

                    Text(row.endTime)
                        .font(AppFont.semibold(15, relativeTo: .subheadline))
                        .foregroundStyle(AppTheme.textSecondary)
                        .monospacedDigit()
                        .lineLimit(1)
                }
            }
            .frame(width: 76, height: cardHeight, alignment: .center)

            Color.clear
            .frame(minHeight: Self.minimumCardHeight, alignment: .top)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                ZStack(alignment: .leading) {
                    cardShape
                        .fill(accentColor.opacity(0.95))

                    cardShape
                        .fill(AppTheme.surfacePrimary)
                        .padding(.leading, 4)
                        .overlay {
                            LinearGradient(
                                colors: [
                                    accentColor.opacity(0.10),
                                    accentColor.opacity(0.03),
                                    .clear
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                            .clipShape(cardShape)
                            .padding(.leading, 4)
                        }
                }
            )
            .overlay(alignment: .leading) {
                HStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .center, spacing: 10) {
                            if let badge = row.badge {
                                Text(badge.rawValue)
                                    .font(AppFont.bold(12, relativeTo: .caption))
                                    .foregroundStyle(AuthPalette.primaryStart)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(
                                        Capsule()
                                            .fill(AuthPalette.primaryStart.opacity(0.10))
                                    )
                            }

                            Spacer()

                            Text(row.location)
                                .font(AppFont.medium(14, relativeTo: .subheadline))
                                .foregroundStyle(AppTheme.textSecondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.82)
                        }
                        .frame(minHeight: 28)

                        VStack(alignment: .leading, spacing: 6) {
                            Text(row.title)
                                .font(AppFont.bold(20, relativeTo: .headline))
                                .foregroundStyle(AppTheme.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)

                            Text(row.professor)
                                .font(AppFont.medium(17, relativeTo: .body))
                                .foregroundStyle(AppTheme.textTertiary)
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 16)
                    .padding(.leading, 4)

                    Spacer(minLength: 0)
                }
            }
            .overlay {
                cardShape
                    .stroke(AppTheme.divider, lineWidth: 0.8)
                    .padding(.leading, 4)
            }
            .background {
                GeometryReader { proxy in
                    Color.clear
                        .preference(key: HomeClassCardHeightKey.self, value: proxy.size.height)
                }
            }
        }
        .onPreferenceChange(HomeClassCardHeightKey.self) { newHeight in
            guard newHeight > 0 else { return }
            cardHeight = max(newHeight, Self.minimumCardHeight)
        }
    }
}

private struct HomeClassCardHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 122

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct HomeEmptyCard: View {
    let title: String
    let message: String
    let semesterTitle: String?
    let onSemesterTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Today's Classes")
                    .font(AppFont.extraBold(28, relativeTo: .title2))
                    .foregroundStyle(AppTheme.textPrimary)

                Spacer()

                if let semesterTitle {
                    Button(action: onSemesterTap) {
                        Text(semesterTitle)
                            .font(AppFont.semibold(15, relativeTo: .subheadline))
                            .foregroundStyle(AuthPalette.primaryStart)
                    }
                    .buttonStyle(.plain)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text(title)
                    .font(AppFont.bold(22, relativeTo: .title3))
                    .foregroundStyle(AppTheme.textPrimary)

                Text(message)
                    .font(AppFont.medium(16, relativeTo: .body))
                    .foregroundStyle(AppTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(AppTheme.surfacePrimary)
            )
        }
    }
}

private struct HomeLoadingCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Today's Classes")
                .font(AppFont.extraBold(28, relativeTo: .title2))
                .foregroundStyle(AppTheme.textPrimary)

            VStack(spacing: 14) {
                ForEach(0..<2, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(AppTheme.surfacePrimary)
                        .frame(height: 128)
                        .overlay {
                            RoundedRectangle(cornerRadius: 28, style: .continuous)
                                .stroke(AppTheme.divider, lineWidth: 1)
                        }
                }
            }
        }
    }
}

private enum HomeScheduleEditorDestination: Identifiable {
    case create(HomeScheduleItemType)
    case edit(HomeScheduleItem)

    var id: String {
        switch self {
        case let .create(type):
            return "create-\(type.rawValue)"
        case let .edit(item):
            return "edit-\(item.itemId)"
        }
    }
}

private struct HomeScheduleSection: View {
    let todayDeadlines: [HomeScheduleItem]
    let openTasks: [HomeScheduleItem]
    let completedTasks: [HomeScheduleItem]
    let mutationMessage: String?
    let onQuickAdd: (HomeScheduleItemType) -> Void
    let onToggleCompletion: (HomeScheduleItem) -> Void
    let onEdit: (HomeScheduleItem) -> Void
    let onDelete: (HomeScheduleItem) -> Void
    let onDismissMessage: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Schedule")
                    .font(AppFont.extraBold(28, relativeTo: .title2))
                    .foregroundStyle(AppTheme.textPrimary)

                Spacer()

                Menu {
                    Button {
                        onQuickAdd(.memo)
                    } label: {
                        Label("New Memo", systemImage: HomeScheduleItemType.memo.systemImage)
                    }

                    Button {
                        onQuickAdd(.assignment)
                    } label: {
                        Label("New Assignment", systemImage: HomeScheduleItemType.assignment.systemImage)
                    }
                } label: {
                    Label("Add", systemImage: "plus")
                        .font(AppFont.semibold(15, relativeTo: .subheadline))
                        .foregroundStyle(AuthPalette.primaryStart)
                }
                .accessibilityLabel("Add a schedule item")
            }

            HStack(spacing: 12) {
                HomeQuickAddButton(
                    title: "Quick Memo",
                    systemImage: HomeScheduleItemType.memo.systemImage,
                    action: { onQuickAdd(.memo) }
                )
                HomeQuickAddButton(
                    title: "Assignment",
                    systemImage: HomeScheduleItemType.assignment.systemImage,
                    action: { onQuickAdd(.assignment) }
                )
            }

            if let mutationMessage {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Color.orange)

                    Text(mutationMessage)
                        .font(AppFont.medium(14, relativeTo: .subheadline))
                        .foregroundStyle(AppTheme.textSecondary)

                    Spacer()

                    Button(action: onDismissMessage) {
                        Image(systemName: "xmark")
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Dismiss schedule error")
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(AppTheme.surfacePrimary)
                )
            }

            HomeScheduleList(
                title: "Today's Deadlines",
                emptyMessage: "No deadlines due today.",
                items: todayDeadlines,
                onToggleCompletion: onToggleCompletion,
                onEdit: onEdit,
                onDelete: onDelete
            )

            HomeScheduleList(
                title: "Open Tasks",
                emptyMessage: "No open tasks. Add a memo or assignment when something comes up.",
                items: openTasks,
                onToggleCompletion: onToggleCompletion,
                onEdit: onEdit,
                onDelete: onDelete
            )

            HomeScheduleList(
                title: "Completed",
                emptyMessage: "Completed items will stay here so you can reopen or manage them.",
                items: completedTasks,
                onToggleCompletion: onToggleCompletion,
                onEdit: onEdit,
                onDelete: onDelete
            )
        }
    }
}

private struct HomeQuickAddButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(AppFont.semibold(15, relativeTo: .subheadline))
                .foregroundStyle(AppTheme.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(AppTheme.surfacePrimary)
                        .overlay {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(AppTheme.divider, lineWidth: 1)
                        }
                )
        }
        .buttonStyle(.plain)
    }
}

private struct HomeScheduleList: View {
    let title: String
    let emptyMessage: String
    let items: [HomeScheduleItem]
    let onToggleCompletion: (HomeScheduleItem) -> Void
    let onEdit: (HomeScheduleItem) -> Void
    let onDelete: (HomeScheduleItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(AppFont.bold(20, relativeTo: .headline))
                .foregroundStyle(AppTheme.textPrimary)

            VStack(spacing: 0) {
                if items.isEmpty {
                    Text(emptyMessage)
                        .font(AppFont.medium(15, relativeTo: .subheadline))
                        .foregroundStyle(AppTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(18)
                } else {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        HomeScheduleItemRow(
                            item: item,
                            onToggleCompletion: { onToggleCompletion(item) },
                            onEdit: { onEdit(item) },
                            onDelete: { onDelete(item) }
                        )

                        if index < items.count - 1 {
                            Divider()
                                .padding(.leading, 54)
                        }
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(AppTheme.surfacePrimary)
            )
        }
    }
}

private struct HomeScheduleItemRow: View {
    let item: HomeScheduleItem
    let onToggleCompletion: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button(action: onToggleCompletion) {
                Image(systemName: item.completed ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 25, weight: .semibold))
                    .foregroundStyle(item.completed ? AuthPalette.primaryStart : AppTheme.textSecondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(item.completed ? "Mark \(item.title) incomplete" : "Mark \(item.title) complete")

            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 8) {
                    Label(item.type.displayName, systemImage: item.type.systemImage)
                        .font(AppFont.bold(12, relativeTo: .caption))
                        .foregroundStyle(AuthPalette.primaryStart)

                    if let lectureName = item.lectureName {
                        Text(lectureName)
                            .font(AppFont.medium(12, relativeTo: .caption))
                            .foregroundStyle(AppTheme.textSecondary)
                            .lineLimit(1)
                    }
                }

                Text(item.title)
                    .font(AppFont.bold(17, relativeTo: .body))
                    .foregroundStyle(AppTheme.textPrimary)
                    .strikethrough(item.completed, color: AppTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let memo = item.memo, memo.isEmpty == false {
                    Text(memo)
                        .font(AppFont.medium(14, relativeTo: .subheadline))
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineLimit(2)
                }

                if let dueAt = item.dueAt {
                    Label {
                        Text(dueAt.formatted(date: .abbreviated, time: .shortened))
                    } icon: {
                        Image(systemName: "clock")
                    }
                    .font(AppFont.medium(13, relativeTo: .caption))
                    .foregroundStyle(AppTheme.textTertiary)
                }
            }

            Spacer(minLength: 8)

            Menu {
                Button(action: onEdit) {
                    Label("Edit", systemImage: "pencil")
                }
                Button(role: .destructive, action: onDelete) {
                    Label("Delete", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(AppTheme.textSecondary)
                    .frame(width: 34, height: 34)
            }
            .accessibilityLabel("Actions for \(item.title)")
        }
        .padding(16)
    }
}

private struct HomeScheduleEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: HomeViewModel

    let destination: HomeScheduleEditorDestination
    let lectureOptions: [HomeScheduleLectureOption]
    let dueDateRange: ClosedRange<Date>

    @State private var type: HomeScheduleItemType
    @State private var title: String
    @State private var memo: String
    @State private var selectedLectureId: Int64?
    @State private var hasDueDate: Bool
    @State private var dueAt: Date
    @State private var isSaving = false

    init(
        viewModel: HomeViewModel,
        destination: HomeScheduleEditorDestination,
        lectureOptions: [HomeScheduleLectureOption]
    ) {
        self.viewModel = viewModel
        self.destination = destination
        self.lectureOptions = lectureOptions

        let requestedDueDate: Date?
        switch destination {
        case .create:
            requestedDueDate = nil
        case let .edit(item):
            requestedDueDate = item.dueAt
        }
        let dateConfiguration = viewModel.scheduleEditorDateConfiguration(for: requestedDueDate)
        dueDateRange = dateConfiguration.range

        switch destination {
        case let .create(type):
            _type = State(initialValue: type)
            _title = State(initialValue: "")
            _memo = State(initialValue: "")
            _selectedLectureId = State(initialValue: nil)
            _hasDueDate = State(initialValue: type != .memo)
            _dueAt = State(initialValue: dateConfiguration.selection)
        case let .edit(item):
            _type = State(initialValue: item.type)
            _title = State(initialValue: item.title)
            _memo = State(initialValue: item.memo ?? "")
            _selectedLectureId = State(initialValue: item.lectureId)
            _hasDueDate = State(initialValue: item.dueAt != nil)
            _dueAt = State(initialValue: dateConfiguration.selection)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Item") {
                    Picker("Type", selection: $type) {
                        ForEach(HomeScheduleItemType.allCases, id: \.self) { option in
                            Label(option.displayName, systemImage: option.systemImage)
                                .tag(option)
                        }
                    }

                    TextField("Title", text: $title)
                        .textInputAutocapitalization(.sentences)

                    TextField("Notes (optional)", text: $memo, axis: .vertical)
                        .lineLimit(2...5)
                }

                Section("Lecture") {
                    Picker("Associated lecture", selection: $selectedLectureId) {
                        Text("No lecture")
                            .tag(Int64?.none)
                        ForEach(lectureOptions) { lecture in
                            Text(lecture.name)
                                .tag(Int64?.some(lecture.id))
                        }
                    }
                }

                Section("Deadline") {
                    Toggle("Add deadline", isOn: $hasDueDate)
                    if hasDueDate {
                        DatePicker(
                            "Due",
                            selection: $dueAt,
                            in: dueDateRange,
                            displayedComponents: [.date, .hourAndMinute]
                        )
                    }
                }

                if let message = viewModel.scheduleMutationMessage {
                    Section {
                        Text(message)
                            .foregroundStyle(Color.red)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.pageBackground.ignoresSafeArea())
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(isSaving)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving…" : "Save") {
                        Task {
                            await save()
                        }
                    }
                    .disabled(isSaving || trimmedTitle.isEmpty)
                }
            }
        }
    }

    private var navigationTitle: String {
        switch destination {
        case .create:
            return "New Schedule Item"
        case .edit:
            return "Edit Schedule Item"
        }
    }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }

        let trimmedMemo = memo.trimmingCharacters(in: .whitespacesAndNewlines)
        let completed: Bool
        if case let .edit(item) = destination {
            completed = item.completed
        } else {
            completed = false
        }

        let input = HomeScheduleItemInput(
            lectureId: selectedLectureId,
            type: type,
            title: trimmedTitle,
            memo: trimmedMemo.isEmpty ? nil : trimmedMemo,
            dueAt: hasDueDate ? dueAt : nil,
            completed: completed
        )

        let saved: Bool
        switch destination {
        case .create:
            saved = await viewModel.createScheduleItem(input)
        case let .edit(item):
            saved = await viewModel.updateScheduleItem(itemId: item.itemId, input: input)
        }

        if saved {
            dismiss()
        }
    }
}

private struct HomeTrendingPostsSection: View {
    let posts: [HotPostSummary]
    let onBoardsTap: () -> Void
    let onPostTap: (Int64) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label {
                    Text("Trending Posts")
                        .font(AppFont.extraBold(24, relativeTo: .title3))
                        .foregroundStyle(AppTheme.textPrimary)
                } icon: {
                    Image(systemName: "flame.fill")
                        .foregroundStyle(Color(red: 0.98, green: 0.32, blue: 0.26))
                }

                Spacer()

                Button(action: onBoardsTap) {
                    Text("To Boards")
                        .font(AppFont.semibold(15, relativeTo: .subheadline))
                        .foregroundStyle(AuthPalette.primaryStart)
                }
                .buttonStyle(.plain)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(posts) { post in
                        Button {
                            onPostTap(post.id)
                        } label: {
                            HomeTrendingPostCard(post: post)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.trailing, 4)
            }
        }
    }
}

private struct HomeTrendingPostCard: View {
    let post: HotPostSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(post.boardName.uppercased())
                    .font(AppFont.bold(10, relativeTo: .caption))
                    .foregroundStyle(AuthPalette.primaryStart)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule(style: .continuous)
                            .fill(AuthPalette.primaryStart.opacity(0.10))
                    )

                Spacer()

                Text(post.relativeCreatedAt)
                    .font(AppFont.medium(13, relativeTo: .caption))
                    .foregroundStyle(AppTheme.textSecondary)
            }

            Text(post.title)
                .font(AppFont.bold(18, relativeTo: .headline))
                .foregroundStyle(AppTheme.textPrimary)
                .lineLimit(3)
                .multilineTextAlignment(.leading)

            Spacer(minLength: 8)

            HStack(spacing: 16) {
                Label("\(post.likeCount)", systemImage: "heart.fill")
                    .font(AppFont.medium(14, relativeTo: .caption))
                    .foregroundStyle(Color.red)

                Label("\(post.commentCount)", systemImage: "message.fill")
                    .font(AppFont.medium(14, relativeTo: .caption))
                    .foregroundStyle(Color(red: 0.28, green: 0.27, blue: 0.88))
            }
        }
        .padding(20)
        .frame(width: 286, height: 172, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(AppTheme.surfacePrimary)
                .shadow(color: Color.black.opacity(0.05), radius: 14, y: 6)
        )
    }
}

struct HomeView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            HomeView(
                session: PreviewFactory.makeSession(state: .authenticated),
                client: PreviewHomeClient.loaded(),
                boardsSyncStore: BoardsSyncStore(),
                nowProvider: { PreviewHomeData.previewNow }
            )
            .previewDisplayName("Home Loaded - Standard")

            HomeView(
                session: PreviewFactory.makeSession(state: .authenticated),
                client: PreviewHomeClient.loaded(),
                boardsSyncStore: BoardsSyncStore(),
                nowProvider: { PreviewHomeData.previewNow }
            )
            .preferredColorScheme(.dark)
            .previewDisplayName("Home Loaded - Dark")

            HomeView(
                session: PreviewFactory.makeSession(state: .authenticated),
                client: PreviewHomeClient(scenario: .loadedLongTitle),
                boardsSyncStore: BoardsSyncStore(),
                nowProvider: { PreviewHomeData.previewNow }
            )
            .previewDisplayName("Home Loaded - Long Title")

            HomeView(
                session: PreviewFactory.makeSession(state: .authenticated),
                client: PreviewHomeClient(scenario: .noClassesToday),
                boardsSyncStore: BoardsSyncStore(),
                nowProvider: { PreviewHomeData.previewNow }
            )
            .previewDisplayName("Home No Classes")

            HomeView(
                session: PreviewFactory.makeSession(state: .authenticated),
                client: PreviewHomeClient(scenario: .networkFailure),
                boardsSyncStore: BoardsSyncStore(),
                nowProvider: { PreviewHomeData.previewNow }
            )
            .previewDisplayName("Home Failure")

            HomeView(
                session: PreviewFactory.makeSession(state: .authenticated),
                client: PreviewHomeClient.loaded(),
                boardsSyncStore: BoardsSyncStore(),
                nowProvider: { PreviewHomeData.previewNow }
            )
            .preferredColorScheme(.dark)
            .previewDisplayName("Home Loaded - Dark")

            HomeView(
                session: PreviewFactory.makeSession(state: .authenticated),
                client: PreviewHomeClient(scenario: .networkFailure),
                boardsSyncStore: BoardsSyncStore(),
                nowProvider: { PreviewHomeData.previewNow }
            )
            .preferredColorScheme(.dark)
            .previewDisplayName("Home Failure - Dark")
        }
    }
}
