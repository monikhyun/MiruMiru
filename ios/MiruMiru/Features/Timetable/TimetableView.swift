import SwiftUI

struct TimetableView: View {
    @ObservedObject private var session: AppSession
    @StateObject private var viewModel: TimetableViewModel
    private let isActive: Bool

    @State private var isCatalogPresented = false
    @State private var searchQuery = ""
    @State private var selectedFilter: TimetableCatalogFilter = .all
    @State private var focusSearchOnPresent = false
    @State private var selectedLecture: TimetableLectureItem?
    @State private var removalTarget: TimetableLectureItem?

    init(
        session: AppSession,
        client: TimetableClientProtocol,
        isActive: Bool = true
    ) {
        self.session = session
        self.isActive = isActive
        _viewModel = StateObject(wrappedValue: TimetableViewModel(client: client))
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    header

                    if let message = viewModel.actionMessage {
                        TimetableMessageBanner(message: message) {
                            viewModel.clearActionMessage()
                        }
                    }

                    weekdayHeader

                    content
                }
                .padding(.horizontal, 10)
                .padding(.top, 18)
                .padding(.bottom, AuthenticatedLayoutMetrics.rootContentBottomSpacing)
            }
            .background(background)
            .task(id: isActive) {
                guard isActive else { return }
                await viewModel.loadIfNeeded()
            }
            .onChange(of: viewModel.invalidateStateIfNeeded()) { _, shouldInvalidate in
                guard shouldInvalidate else { return }
                session.invalidateSession()
            }
            .sheet(isPresented: $isCatalogPresented, onDismiss: resetCatalogPresentation) {
                TimetableCatalogSheet(
                    lectures: viewModel.filteredCatalog(query: searchQuery, filter: selectedFilter),
                    filters: viewModel.availableCatalogFilters,
                    filter: $selectedFilter,
                    query: $searchQuery,
                    memberContext: currentMemberContext,
                    isLoading: {
                        if case .loading = viewModel.catalogState { return true }
                        return false
                    }(),
                    errorMessage: catalogErrorMessage,
                    actionMessage: viewModel.catalogActionMessage,
                    focusSearchOnAppear: focusSearchOnPresent,
                    addedLectureIds: currentAddedLectureIds,
                    onClose: {
                        viewModel.clearCatalogActionMessage()
                        isCatalogPresented = false
                    },
                    onDismissError: {
                        viewModel.clearCatalogFailure()
                    },
                    onDismissActionMessage: {
                        viewModel.clearCatalogActionMessage()
                    },
                    onAdd: { lectureId in
                        Task { await viewModel.addLecture(lectureId, origin: .catalog) }
                    },
                    onRemove: { lectureId in
                        Task { await viewModel.removeLecture(lectureId, origin: .catalog) }
                    }
                )
                .presentationDetents([.fraction(0.76), .large])
                .presentationDragIndicator(.hidden)
                .presentationBackground(.clear)
                .task {
                    await viewModel.loadCatalogIfNeeded()
                }
            }
            .sheet(item: $selectedLecture) { lecture in
                TimetableLectureDetailSheet(
                    lecture: lecture,
                    primaryActionTitle: "Remove from Timetable",
                    primaryActionColor: Color(red: 0.94, green: 0.27, blue: 0.25),
                    primaryActionConfirmationTitle: "Remove this course from your timetable?",
                    onClose: {
                        selectedLecture = nil
                    },
                    onPrimaryAction: {
                        selectedLecture = nil
                        Task { await viewModel.removeLecture(lecture.id) }
                    },
                    colorOptions: viewModel.customColorOptions(for: lecture.id),
                    selectedColorIndex: viewModel.customColorIndex(for: lecture.id),
                    onSelectColor: { colorIndex in
                        _ = viewModel.setCustomColorIndex(colorIndex, for: lecture.id)
                    },
                    onClearColor: {
                        viewModel.clearCustomColorIndex(for: lecture.id)
                    }
                )
                .presentationDetents([.fraction(0.92), .large])
                .presentationDragIndicator(.hidden)
            }
            .alert(item: $removalTarget) { lecture in
                Alert(
                    title: Text("Remove Course"),
                    message: Text("Remove \(lecture.name) from your timetable?"),
                    primaryButton: .destructive(Text("Remove")) {
                        Task { await viewModel.removeLecture(lecture.id) }
                    },
                    secondaryButton: .cancel()
                )
            }
        }
    }

    private var background: some View {
        AppTheme.pageBackground.ignoresSafeArea()
    }

    @ViewBuilder
    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Menu {
                    ForEach(viewModel.semesters) { semester in
                        Button(semester.titleText) {
                            handleSemesterChange(semester.id)
                        }
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(selectedSemesterTitle)
                            .font(AppFont.extraBold(22, relativeTo: .title))
                            .foregroundStyle(AppTheme.textPrimary)
                            .lineLimit(2)
                            .minimumScaleFactor(0.82)

                        Text("Tap to change semester")
                            .font(AppFont.medium(13, relativeTo: .footnote))
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                }
                .buttonStyle(.plain)
            }

            Spacer(minLength: 12)

            HStack(spacing: 0) {
                Button {
                    focusSearchOnPresent = false
                    isCatalogPresented = true
                } label: {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [AuthPalette.primaryStart, AuthPalette.primaryEnd],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 54, height: 54)
                            .shadow(color: AuthPalette.primaryShadow, radius: 10, y: 6)

                        Image(systemName: "plus")
                            .font(.system(size: 21, weight: .bold))
                            .foregroundStyle(Color.white)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var weekdayHeader: some View {
        HStack(spacing: 8) {
            Spacer()
                .frame(width: 26)

            ForEach(Array(zip(["Mon", "Tue", "Wed", "Thu", "Fri"].indices, ["Mon", "Tue", "Wed", "Thu", "Fri"])), id: \.0) { _, day in
                Text(day)
                    .font(AppFont.bold(15, relativeTo: .subheadline))
                    .foregroundStyle(AppTheme.textPrimary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.screenState {
        case .loading:
            TimetableLoadingState()
        case let .failed(failure):
            TimetableFailureState(message: failure.message) {
                Task { await viewModel.reload() }
            }
        case let .empty(content):
            TimetableGridSection(
                hourRange: content.hourRange,
                blocks: [],
                markers: content.markers,
                overlay: AnyView(
                    TimetableEmptyOverlay(
                        title: content.state.title,
                        message: content.state.message
                    ) {
                        focusSearchOnPresent = false
                        isCatalogPresented = true
                    }
                ),
                onTapBlock: { _ in }
            )
        case let .loaded(content):
            TimetableGridSection(
                hourRange: content.hourRange,
                blocks: content.blocks,
                markers: content.markers,
                overlay: nil,
                onTapBlock: { block in
                    if let lecture = currentTimetableLecture(id: block.lectureId) {
                        selectedLecture = lecture
                    }
                }
            )
        }
    }

    private var selectedSemesterTitle: String {
        if let selected = viewModel.semesters.first(where: { $0.id == viewModel.selectedSemesterId }) {
            return selected.titleText
        }

        switch viewModel.screenState {
        case let .loaded(content):
            return content.selectedSemester.titleText
        case let .empty(content):
            return content.selectedSemester?.titleText ?? "Timetable"
        default:
            return "Timetable"
        }
    }

    private var currentMemberContext: TimetableMemberContext? {
        switch viewModel.screenState {
        case let .loaded(content):
            return content.memberContext
        case let .empty(content):
            return content.memberContext
        default:
            return nil
        }
    }

    private var currentAddedLectureIds: Set<Int64> {
        switch viewModel.screenState {
        case let .loaded(content):
            return content.addedLectureIds
        default:
            return []
        }
    }

    private var catalogErrorMessage: String? {
        if case let .failed(failure) = viewModel.catalogState {
            return failure.message
        }
        return nil
    }

    private func currentTimetableLecture(id: Int64) -> TimetableLectureItem? {
        switch viewModel.screenState {
        case let .loaded(content):
            return content.lectures.first(where: { $0.id == id }) ?? currentCatalogLecture(id: id)
        default:
            return currentCatalogLecture(id: id)
        }
    }

    private func currentCatalogLecture(id: Int64) -> TimetableLectureItem? {
        guard case let .loaded(catalog) = viewModel.catalogState else { return nil }
        return catalog.first(where: { $0.id == id })
    }

    private func handleSemesterChange(_ semesterId: Int64) {
        resetCatalogPresentation()
        isCatalogPresented = false
        Task {
            await viewModel.selectSemester(semesterId)
        }
    }

    private func resetCatalogPresentation() {
        searchQuery = ""
        selectedFilter = .all
        focusSearchOnPresent = false
        viewModel.clearCatalogActionMessage()
    }
}

private struct TimetableGridSection: View {
    let hourRange: TimetableHourRange
    let blocks: [TimetableGridBlock]
    let markers: [TimetableGridMarker]
    let overlay: AnyView?
    let onTapBlock: (TimetableGridBlock) -> Void

    private let timeRailWidth: CGFloat = 22
    private let columnSpacing: CGFloat = 6
    private let outerSpacing: CGFloat = 4
    private let rowSpacing: CGFloat = 6
    private let rowHeight: CGFloat = 82

    var body: some View {
        GeometryReader { proxy in
            let dayColumnWidth = max(58, (proxy.size.width - timeRailWidth - outerSpacing - (columnSpacing * 4)) / 5)
            let trackHeight = rowHeight + rowSpacing
            let totalHeight = (CGFloat(hourRange.hours.count) * trackHeight) - rowSpacing
            let gridWidth = (dayColumnWidth * 5) + (columnSpacing * 4)

            HStack(alignment: .top, spacing: outerSpacing) {
                VStack(alignment: .leading, spacing: rowSpacing) {
                    ForEach(hourRange.hours, id: \.self) { hour in
                        VStack(spacing: 4) {
                            Text(hourLabel(hour))
                                .font(AppFont.medium(12, relativeTo: .caption))
                                .monospacedDigit()
                                .foregroundStyle(AppTheme.textTertiary)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            Spacer(minLength: 0)
                        }
                        .frame(height: rowHeight, alignment: .topLeading)
                    }
                }
                .frame(width: timeRailWidth)

                ZStack(alignment: .topLeading) {
                    VStack(spacing: rowSpacing) {
                        ForEach(hourRange.hours, id: \.self) { _ in
                            HStack(spacing: columnSpacing) {
                                ForEach(0..<5, id: \.self) { _ in
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(AppTheme.surfaceSecondary)
                                        .overlay {
                                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                .stroke(AppTheme.divider, lineWidth: 1)
                                        }
                                        .frame(width: dayColumnWidth, height: rowHeight)
                                }
                            }
                        }
                    }

                    ForEach(markers) { marker in
                        TimetableGridMarkerRow(marker: marker)
                            .frame(
                                width: gridWidth,
                                height: markerHeight(for: marker, trackHeight: trackHeight)
                            )
                            .offset(
                                y: markerOffset(for: marker, trackHeight: trackHeight, rangeStartHour: hourRange.startHour)
                            )
                    }

                    ForEach(blocks) { block in
                        Button {
                            onTapBlock(block)
                        } label: {
                            TimetableLectureBlock(block: block)
                        }
                        .buttonStyle(.plain)
                            .frame(
                                width: dayColumnWidth,
                                height: blockHeight(for: block, trackHeight: trackHeight)
                            )
                            .offset(
                                x: CGFloat(block.dayIndex) * (dayColumnWidth + columnSpacing),
                                y: blockOffset(for: block, trackHeight: trackHeight, rangeStartHour: hourRange.startHour)
                            )
                            .accessibilityLabel(accessibilityLabel(for: block))
                            .accessibilityHint("Opens course details")
                    }

                    if let overlay {
                        overlay
                            .frame(width: gridWidth, height: totalHeight)
                    }
                }
                .frame(width: gridWidth, height: totalHeight, alignment: .topLeading)
                .clipped()
            }
        }
        .frame(height: (CGFloat(hourRange.hours.count) * (rowHeight + rowSpacing)) - rowSpacing)
    }

    private func hourLabel(_ hour: Int) -> String {
        String(hour)
    }

    private func blockOffset(for block: TimetableGridBlock, trackHeight: CGFloat, rangeStartHour: Int) -> CGFloat {
        let rangeStartMinutes = rangeStartHour * 60
        let delta = block.startMinutes - rangeStartMinutes
        return (CGFloat(delta) / 60.0) * trackHeight
    }

    private func blockHeight(for block: TimetableGridBlock, trackHeight: CGFloat) -> CGFloat {
        let duration = CGFloat(block.endMinutes - block.startMinutes) / 60.0
        return max(rowHeight, (duration * trackHeight) - rowSpacing)
    }

    private func accessibilityLabel(for block: TimetableGridBlock) -> String {
        "\(block.title), \(block.professor), \(block.location)"
    }

    private func markerOffset(for marker: TimetableGridMarker, trackHeight: CGFloat, rangeStartHour: Int) -> CGFloat {
        let rangeStartMinutes = rangeStartHour * 60
        let delta = marker.startMinutes - rangeStartMinutes
        return max(0, (CGFloat(delta) / 60.0) * trackHeight)
    }

    private func markerHeight(for marker: TimetableGridMarker, trackHeight: CGFloat) -> CGFloat {
        let duration = CGFloat(marker.endMinutes - marker.startMinutes) / 60.0
        return max(34, (duration * trackHeight) - rowSpacing)
    }
}

private struct TimetableGridMarkerRow: View {
    let marker: TimetableGridMarker
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Color.orange.opacity(colorScheme == .dark ? 0.20 : 0.12))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(
                        Color.orange.opacity(colorScheme == .dark ? 0.58 : 0.42),
                        style: StrokeStyle(lineWidth: 1, dash: [6, 4])
                    )
            }
            .overlay(alignment: .leading) {
                Text(marker.title)
                    .font(AppFont.bold(11, relativeTo: .caption2))
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(1)
                    .padding(.horizontal, 10)
            }
            .allowsHitTesting(false)
    }
}

private struct TimetableLectureBlock: View {
    let block: TimetableGridBlock
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = TimetablePalette.token(for: block.accentIndex, colorScheme: colorScheme)
        let cardShape = RoundedRectangle(cornerRadius: 12, style: .continuous)

        cardShape
            .fill(
                LinearGradient(
                    colors: palette.gradientColors,
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .overlay {
                cardShape
                    .strokeBorder(palette.border, lineWidth: 1.35)
            }
            .overlay {
                cardShape
                    .inset(by: 1.4)
                    .strokeBorder(palette.innerHighlight, lineWidth: 0.65)
            }
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(palette.accent.opacity(colorScheme == .dark ? 0.58 : 0.68))
                    .frame(width: 4)
                    .padding(.leading, 6)
                    .padding(.vertical, 8)
            }
            .overlay(alignment: .leading) {
                HStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(block.title)
                            .font(AppFont.bold(12, relativeTo: .subheadline))
                            .foregroundStyle(palette.title)
                            .lineLimit(2)

                        Text(block.professor)
                            .font(AppFont.semibold(10, relativeTo: .caption2))
                            .foregroundStyle(palette.subtitle)
                            .lineLimit(1)

                        Text(block.location)
                            .font(AppFont.medium(10, relativeTo: .caption2))
                            .foregroundStyle(palette.caption)
                            .lineLimit(2)
                    }
                    .padding(.leading, 18)
                    .padding(.trailing, 9)
                    .padding(.vertical, 8)

                    Spacer(minLength: 0)
                }
            }
            .shadow(color: palette.edgeShadow, radius: 3, x: 0, y: 1)
        .contentShape(Rectangle())
    }
}

private struct TimetableLectureDetailSheet: View {
    let lecture: TimetableLectureItem
    let primaryActionTitle: String
    let primaryActionColor: Color
    let primaryActionConfirmationTitle: String?
    let onClose: () -> Void
    let onPrimaryAction: () -> Void
    let colorOptions: [TimetableColorPickerOption]
    let selectedColorIndex: Int?
    let onSelectColor: ((Int) -> Void)?
    let onClearColor: (() -> Void)?

    @State private var isShowingPrimaryActionConfirmation = false

    init(
        lecture: TimetableLectureItem,
        primaryActionTitle: String,
        primaryActionColor: Color,
        primaryActionConfirmationTitle: String?,
        onClose: @escaping () -> Void,
        onPrimaryAction: @escaping () -> Void,
        colorOptions: [TimetableColorPickerOption] = [],
        selectedColorIndex: Int? = nil,
        onSelectColor: ((Int) -> Void)? = nil,
        onClearColor: (() -> Void)? = nil
    ) {
        self.lecture = lecture
        self.primaryActionTitle = primaryActionTitle
        self.primaryActionColor = primaryActionColor
        self.primaryActionConfirmationTitle = primaryActionConfirmationTitle
        self.onClose = onClose
        self.onPrimaryAction = onPrimaryAction
        self.colorOptions = colorOptions
        self.selectedColorIndex = selectedColorIndex
        self.onSelectColor = onSelectColor
        self.onClearColor = onClearColor
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                TimetableDetailSheetTopBar(onClose: onClose)
                TimetableDetailHeroSection(lecture: lecture)
                if colorOptions.isEmpty == false {
                    TimetableColorPickerSection(
                        options: colorOptions,
                        selectedColorIndex: selectedColorIndex,
                        onSelectColor: onSelectColor,
                        onClearColor: onClearColor
                    )
                }
                TimetableDetailMetricsGrid(lecture: lecture)
                TimetableDetailMetaSection(lecture: lecture)
                TimetableDetailLocationPanel(lecture: lecture)
                actionSection
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 30)
        }
        .background(AppTheme.pageBackground.ignoresSafeArea())
        .confirmationDialog(
            primaryActionConfirmationTitle ?? "",
            isPresented: $isShowingPrimaryActionConfirmation,
            titleVisibility: .visible
        ) {
            Button(primaryActionTitle, role: .destructive) {
                onPrimaryAction()
            }

            Button("Cancel", role: .cancel) { }
        } message: {
            Text(lecture.name)
        }
    }

    private var actionSection: some View {
        VStack(spacing: 14) {
            Button {
                if primaryActionConfirmationTitle == nil {
                    onPrimaryAction()
                } else {
                    isShowingPrimaryActionConfirmation = true
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: primaryActionConfirmationTitle == nil ? "plus" : "trash")
                        .font(.system(size: 17, weight: .bold))

                    Text(primaryActionTitle)
                        .font(AppFont.bold(18, relativeTo: .headline))
                }
                .foregroundStyle(Color.white)
                .frame(maxWidth: .infinity)
                .frame(height: 60)
                .background(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(primaryActionColor)
                        .shadow(color: primaryActionColor.opacity(0.22), radius: 16, y: 10)
                )
            }
            .buttonStyle(.plain)

            Button(action: onClose) {
                Text("Close")
                    .font(AppFont.bold(18, relativeTo: .headline))
                    .foregroundStyle(AppTheme.textPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 58)
                    .background(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(AppTheme.surfaceSecondary)
                    )
            }
            .buttonStyle(.plain)
        }
    }
}

private struct TimetableDetailSheetTopBar: View {
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Capsule()
                .fill(AppTheme.handle)
                .frame(width: 42, height: 8)
                .frame(maxWidth: .infinity)

            HStack {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(AppTheme.textSecondary)
                        .frame(width: 40, height: 40)
                }
                .buttonStyle(.plain)

                Spacer()

                Text("Course Details")
                    .font(AppFont.extraBold(24, relativeTo: .title2))
                    .foregroundStyle(AppTheme.textPrimary)

                Spacer()

                Image(systemName: "ellipsis")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(AppTheme.textTertiary)
                    .frame(width: 40, height: 40)
            }
        }
    }
}

private struct TimetableDetailHeroSection: View {
    let lecture: TimetableLectureItem

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(lecture.name)
                .font(AppFont.extraBold(28, relativeTo: .title))
                .foregroundStyle(AppTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Text(lecture.professor)
                .font(AppFont.medium(18, relativeTo: .title3))
                .foregroundStyle(AppTheme.textSecondary)
        }
    }
}

private struct TimetableColorPickerSection: View {
    let options: [TimetableColorPickerOption]
    let selectedColorIndex: Int?
    let onSelectColor: ((Int) -> Void)?
    let onClearColor: (() -> Void)?
    @Environment(\.colorScheme) private var colorScheme

    private let columns = [
        GridItem(.adaptive(minimum: 34, maximum: 42), spacing: 10)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Text("Course Color")
                    .font(AppFont.bold(16, relativeTo: .headline))
                    .foregroundStyle(AppTheme.textPrimary)

                Spacer()

                if selectedColorIndex != nil, let onClearColor {
                    Button(action: onClearColor) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(AppTheme.textSecondary)
                            .frame(width: 36, height: 36)
                            .background(
                                Circle()
                                    .fill(AppTheme.surfaceSecondary)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Use automatic color")
                }
            }

            LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                ForEach(options) { option in
                    Button {
                        guard option.isDisabled == false else { return }
                        onSelectColor?(option.token.index)
                    } label: {
                        ZStack {
                            Circle()
                                .fill(TimetablePalette.swatchColor(for: option.token, colorScheme: colorScheme))
                                .frame(width: 34, height: 34)
                                .overlay {
                                    Circle()
                                        .stroke(AppTheme.divider, lineWidth: 1)
                                }

                            if option.isSelected {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 13, weight: .black))
                                    .foregroundStyle(Color.white)
                                    .shadow(color: Color.black.opacity(0.35), radius: 2, y: 1)
                            }

                            if option.isDisabled {
                                Circle()
                                    .fill(AppTheme.surfacePrimary.opacity(colorScheme == .dark ? 0.72 : 0.78))
                                    .frame(width: 34, height: 34)

                                Image(systemName: "slash")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundStyle(AppTheme.textTertiary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(option.isDisabled)
                    .accessibilityLabel(option.token.name)
                }
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(AppTheme.surfacePrimary)
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(AppTheme.divider, lineWidth: 1)
                }
        )
    }
}

private struct TimetableDetailMetricsGrid: View {
    let lecture: TimetableLectureItem

    var body: some View {
        VStack(spacing: 14) {
            TimetableDetailScheduleCard(lecture: lecture)

            HStack(alignment: .top, spacing: 14) {
                TimetableDetailMetricCard(
                    title: "Location",
                    value: lecture.primaryLocation,
                    iconName: "mappin.and.ellipse",
                    accent: Color(red: 0.63, green: 0.68, blue: 0.77)
                )

                TimetableDetailMetricCard(
                    title: "Credits",
                    value: "\(lecture.credit) Credits",
                    iconName: "graduationcap.fill",
                    accent: Color(red: 0.63, green: 0.68, blue: 0.77)
                )
            }
        }
    }
}

private struct TimetableDetailScheduleCard: View {
    let lecture: TimetableLectureItem

    var body: some View {
        let cardShape = RoundedRectangle(cornerRadius: 24, style: .continuous)

        ZStack(alignment: .leading) {
            cardShape
                .fill(AuthPalette.primaryStart.opacity(0.95))

            cardShape
                .fill(AppTheme.surfaceSecondary)
                .padding(.leading, 4)
                .overlay {
                    LinearGradient(
                        colors: [
                            AuthPalette.primaryStart.opacity(0.10),
                            AuthPalette.primaryStart.opacity(0.03),
                            .clear
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .clipShape(cardShape)
                    .padding(.leading, 4)
                }

            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 14) {
                    Image(systemName: "calendar")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(AuthPalette.primaryStart)

                    Text("Schedule")
                        .font(AppFont.bold(13, relativeTo: .caption))
                        .foregroundStyle(AuthPalette.primaryStart)
                        .textCase(.uppercase)

                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(lecture.orderedSchedules.enumerated()), id: \.offset) { _, schedule in
                            Text("\(weekdayTitle(schedule.dayOfWeek)) \(schedule.startTime) - \(schedule.endTime)")
                                .font(AppFont.bold(17, relativeTo: .headline))
                                .foregroundStyle(AuthPalette.primaryStart)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 20)
                .padding(.leading, 4)

                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay {
            cardShape
                .stroke(AppTheme.divider, lineWidth: 0.8)
                .padding(.leading, 4)
        }
    }
}

private struct TimetableDetailMetricCard: View {
    let title: String
    let value: String
    let iconName: String
    let accent: Color

    var body: some View {
        let cardShape = RoundedRectangle(cornerRadius: 24, style: .continuous)

        ZStack(alignment: .leading) {
            cardShape
                .fill(accent.opacity(0.95))

            cardShape
                .fill(AppTheme.surfaceSecondary)
                .padding(.leading, 4)
                .overlay {
                    LinearGradient(
                        colors: [
                            accent.opacity(0.10),
                            accent.opacity(0.03),
                            .clear
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .clipShape(cardShape)
                    .padding(.leading, 4)
                }

            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 10) {
                    Image(systemName: iconName)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(accent)

                    Text(title)
                        .font(AppFont.bold(12, relativeTo: .caption))
                        .foregroundStyle(AppTheme.textSecondary)
                        .textCase(.uppercase)

                    Text(value)
                        .font(AppFont.bold(16, relativeTo: .headline))
                        .foregroundStyle(AppTheme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 18)
                .padding(.leading, 4)

                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
        .overlay {
            cardShape
                .stroke(AppTheme.divider, lineWidth: 0.8)
                .padding(.leading, 4)
        }
    }
}

private struct TimetableDetailMetaSection: View {
    let lecture: TimetableLectureItem

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Course Information")
                .font(AppFont.bold(16, relativeTo: .headline))
                .foregroundStyle(AppTheme.textPrimary)

            VStack(spacing: 12) {
                detailRow(title: "Course Code", value: lecture.code)
                detailRow(title: "Category", value: lecture.categoryTitle)
            }
        }
    }

    private func detailRow(title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .font(AppFont.semibold(13, relativeTo: .caption))
                .foregroundStyle(AppTheme.textSecondary)
                .frame(width: 98, alignment: .leading)

            Text(value)
                .font(AppFont.medium(16, relativeTo: .body))
                .foregroundStyle(AppTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
    }
}

private struct TimetableDetailLocationPanel: View {
    let lecture: TimetableLectureItem

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Where to Go")
                .font(AppFont.bold(16, relativeTo: .headline))
                .foregroundStyle(AppTheme.textPrimary)

            ZStack {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                AppTheme.surfaceSecondary,
                                AppTheme.surfacePrimary
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .stroke(AppTheme.divider, lineWidth: 1)
                    }

                VStack(spacing: 16) {
                    Image(systemName: "building.2.crop.circle.fill")
                        .font(.system(size: 34, weight: .medium))
                        .foregroundStyle(AuthPalette.primaryStart)

                    Text(lecture.locationSummary)
                        .font(AppFont.bold(21, relativeTo: .title3))
                        .foregroundStyle(AppTheme.textPrimary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("Room information is based on the current timetable schedule.")
                        .font(AppFont.medium(14, relativeTo: .body))
                        .foregroundStyle(AppTheme.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 22)
            }
            .frame(height: 210)
        }
    }
}

private func weekdayTitle(_ dayOfWeek: String) -> String {
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
        return dayOfWeek.capitalized
    }
}

private struct TimetableEmptyOverlay: View {
    let title: String
    let message: String
    let action: () -> Void

    var body: some View {
        VStack {
            Spacer(minLength: 36)

            VStack(alignment: .leading, spacing: 10) {
                Text(title)
                    .font(AppFont.bold(20, relativeTo: .title3))
                    .foregroundStyle(AppTheme.textPrimary)

                Text(message)
                    .font(AppFont.medium(15, relativeTo: .body))
                    .foregroundStyle(AppTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button(action: action) {
                    Text("Add Course")
                        .font(AppFont.bold(15, relativeTo: .headline))
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .background(
                            Capsule()
                                .fill(AuthPalette.primaryStart)
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(20)
            .frame(maxWidth: 280, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(AppTheme.surfacePrimary.opacity(0.96))
                    .shadow(color: Color.black.opacity(0.06), radius: 16, y: 10)
            )

            Spacer(minLength: 0)
        }
    }
}

private struct TimetableMessageBanner: View {
    let message: String
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(Color.orange)

            Text(message)
                .font(AppFont.medium(14, relativeTo: .subheadline))
                .foregroundStyle(AppTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 8)

            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(AppTheme.textSecondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(AppTheme.surfacePrimary)
                .shadow(color: Color.black.opacity(0.04), radius: 10, y: 4)
        )
    }
}

private struct TimetableFailureState: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("We couldn't load your timetable")
                .font(AppFont.bold(22, relativeTo: .title3))
                .foregroundStyle(AppTheme.textPrimary)

            Text(message)
                .font(AppFont.medium(15, relativeTo: .body))
                .foregroundStyle(AppTheme.textSecondary)

            PrimaryActionButton(
                title: "Try Again",
                isLoading: false,
                isDisabled: false,
                height: 58,
                cornerRadius: 18
            ) {
                retry()
            }
        }
        .padding(22)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(AppTheme.surfacePrimary)
                .shadow(color: Color.black.opacity(0.05), radius: 16, y: 8)
        )
    }
}

private struct TimetableLoadingState: View {
    var body: some View {
        VStack(spacing: 12) {
            ForEach(0..<6, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(AppTheme.surfacePrimary)
                    .frame(height: 84)
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(AppTheme.divider, lineWidth: 1)
                    }
            }
        }
    }
}

private struct TimetableCatalogSheet: View {
    let lectures: [TimetableLectureItem]
    let filters: [TimetableCatalogFilter]
    @Binding var filter: TimetableCatalogFilter
    @Binding var query: String
    let memberContext: TimetableMemberContext?
    let isLoading: Bool
    let errorMessage: String?
    let actionMessage: String?
    let focusSearchOnAppear: Bool
    let addedLectureIds: Set<Int64>
    let onClose: () -> Void
    let onDismissError: () -> Void
    let onDismissActionMessage: () -> Void
    let onAdd: (Int64) -> Void
    let onRemove: (Int64) -> Void

    @FocusState private var isSearchFocused: Bool
    @State private var selectedLecture: TimetableLectureItem?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Capsule()
                .fill(AppTheme.handle)
                .frame(width: 42, height: 8)
                .frame(maxWidth: .infinity)
                .padding(.top, 12)

            HStack {
                Text("Add Course")
                    .font(AppFont.extraBold(28, relativeTo: .title2))
                    .foregroundStyle(AppTheme.textPrimary)

                Spacer()

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(AppTheme.textTertiary)
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
            }

            if let actionMessage {
                TimetableMessageBanner(message: actionMessage, dismiss: onDismissActionMessage)
            }

            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(AppTheme.textTertiary)

                TextField("Search by course or professor", text: $query)
                    .font(AppFont.medium(16, relativeTo: .body))
                    .focused($isSearchFocused)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            .padding(.horizontal, 18)
            .frame(height: 60)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(AppTheme.surfaceSecondary)
            )

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(filters, id: \.self) { item in
                        Button {
                            filter = item
                        } label: {
                            Text(chipTitle(for: item))
                                .font(AppFont.bold(14, relativeTo: .subheadline))
                                .foregroundStyle(filter == item ? Color.white : AppTheme.textSecondary)
                                .padding(.horizontal, 18)
                                .padding(.vertical, 12)
                                .background(
                                    Capsule()
                                        .fill(filter == item ? AuthPalette.primaryStart : AppTheme.surfaceSecondary)
                                )
                                .shadow(
                                    color: filter == item ? AuthPalette.primaryShadow : .clear,
                                    radius: 10,
                                    y: 6
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if let errorMessage {
                TimetableMessageBanner(message: errorMessage, dismiss: onDismissError)
            }

            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    if isLoading {
                        ForEach(0..<4, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .fill(AppTheme.surfacePrimary)
                                .frame(height: 108)
                                .shadow(color: Color.black.opacity(0.04), radius: 12, y: 5)
                        }
                    } else if lectures.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("No courses found")
                                .font(AppFont.bold(18, relativeTo: .headline))
                                .foregroundStyle(AppTheme.textPrimary)

                            Text("Try another search or filter.")
                                .font(AppFont.medium(15, relativeTo: .body))
                                .foregroundStyle(AppTheme.textSecondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(20)
                        .background(
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .fill(AppTheme.surfacePrimary)
                        )
                    } else {
                        ForEach(lectures) { lecture in
                            TimetableCatalogLectureCard(
                                lecture: lecture,
                                isAdded: addedLectureIds.contains(lecture.id),
                                onSelect: {
                                    selectedLecture = lecture
                                },
                                onAdd: {
                                    onAdd(lecture.id)
                                },
                                onRemove: {
                                    onRemove(lecture.id)
                                }
                            )
                        }
                    }
                }
                .padding(.bottom, 24)
            }
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 24)
        .background(
            RoundedRectangle(cornerRadius: 36, style: .continuous)
                .fill(AppTheme.backgroundTop)
        )
        .task {
            guard focusSearchOnAppear else { return }
            try? await Task.sleep(nanoseconds: 120_000_000)
            isSearchFocused = true
        }
        .sheet(item: $selectedLecture) { lecture in
            let isAdded = addedLectureIds.contains(lecture.id)

            TimetableLectureDetailSheet(
                lecture: lecture,
                primaryActionTitle: isAdded ? "Remove from Timetable" : "Add to Timetable",
                primaryActionColor: isAdded ? Color(red: 0.94, green: 0.27, blue: 0.25) : AuthPalette.primaryStart,
                primaryActionConfirmationTitle: isAdded ? "Remove this course from your timetable?" : nil,
                onClose: {
                    selectedLecture = nil
                },
                onPrimaryAction: {
                    selectedLecture = nil
                    if isAdded {
                        onRemove(lecture.id)
                    } else {
                        onAdd(lecture.id)
                    }
                }
            )
            .presentationDetents([.fraction(0.92), .large])
            .presentationDragIndicator(.hidden)
        }
    }

    private func chipTitle(for item: TimetableCatalogFilter) -> String {
        switch item {
        case .memberMajor:
            guard let majorName = memberContext?.majorName else { return item.title }
            return majorName.count <= 14 ? majorName : "My Major"
        case let .major(_, name):
            return name.count <= 14 ? name : String(name.prefix(12)) + "..."
        default:
            return item.title
        }
    }
}

private struct TimetableCatalogLectureCard: View {
    let lecture: TimetableLectureItem
    let isAdded: Bool
    let onSelect: () -> Void
    let onAdd: () -> Void
    let onRemove: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = TimetablePalette.token(
            for: TimetableViewModel.accentIndex(for: lecture.id),
            colorScheme: colorScheme
        )

        HStack(spacing: 14) {
            Button(action: onSelect) {
                HStack(spacing: 14) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(palette.accent)
                        .frame(width: 6, height: 104)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(lecture.name)
                            .font(AppFont.bold(18, relativeTo: .headline))
                            .foregroundStyle(AppTheme.textPrimary)
                            .lineLimit(2)

                        Text(lecture.professor)
                            .font(AppFont.medium(15, relativeTo: .body))
                            .foregroundStyle(AppTheme.textSecondary)
                            .lineLimit(1)

                        Text(lecture.primaryLocation)
                            .font(AppFont.medium(14, relativeTo: .subheadline))
                            .foregroundStyle(AppTheme.textSecondary)
                            .lineLimit(1)

                        Text(lecture.scheduleSummary)
                            .font(AppFont.medium(13, relativeTo: .caption))
                            .foregroundStyle(AppTheme.textTertiary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 12)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: isAdded ? onRemove : onAdd) {
                ZStack {
                    Circle()
                        .fill(AppTheme.surfaceSecondary)
                        .frame(width: 52, height: 52)

                    Image(systemName: isAdded ? "checkmark" : "plus")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(isAdded ? palette.accent : AppTheme.textSecondary)
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(AppTheme.surfacePrimary)
                .shadow(color: Color.black.opacity(0.04), radius: 12, y: 6)
        )
    }
}

private enum TimetablePalette {
    struct Token {
        let accent: Color
        let gradientColors: [Color]
        let border: Color
        let innerHighlight: Color
        let edgeShadow: Color
        let title: Color
        let subtitle: Color
        let caption: Color
    }

    static func token(for index: Int, colorScheme: ColorScheme) -> Token {
        let token = TimetableColorWheel.token(for: index)
        let base = RGB(hex: token.hex)
        let accent = swatchColor(for: token, colorScheme: colorScheme)

        let gradientColors: [Color]
        let border: Color
        let innerHighlight: Color
        let edgeShadow: Color
        switch colorScheme {
        case .dark:
            gradientColors = [
                base.mixed(with: .white, amount: 0.24).color.opacity(0.40),
                base.mixed(with: .white, amount: 0.34).color.opacity(0.27),
                base.mixed(with: .white, amount: 0.44).color.opacity(0.14)
            ]
            border = base.mixed(with: .white, amount: 0.30).color.opacity(0.54)
            innerHighlight = Color.white.opacity(0.08)
            edgeShadow = Color.black.opacity(0.20)
        default:
            gradientColors = [
                base.mixed(with: .white, amount: 0.58).color,
                base.mixed(with: .white, amount: 0.76).color,
                base.mixed(with: .white, amount: 0.91).color
            ]
            border = base.mixed(with: .black, amount: 0.12).color.opacity(0.48)
            innerHighlight = Color.white.opacity(0.58)
            edgeShadow = base.mixed(with: .black, amount: 0.18).color.opacity(0.12)
        }

        return Token(
            accent: accent,
            gradientColors: gradientColors,
            border: border,
            innerHighlight: innerHighlight,
            edgeShadow: edgeShadow,
            title: AppTheme.textPrimary,
            subtitle: AppTheme.textSecondary,
            caption: AppTheme.textTertiary
        )
    }

    static func color(for token: TimetableColorToken) -> Color {
        Color(hex: token.hex)
    }

    static func swatchColor(for token: TimetableColorToken, colorScheme: ColorScheme) -> Color {
        let base = RGB(hex: token.hex)
        switch colorScheme {
        case .dark:
            return base.mixed(with: .white, amount: 0.28).color.opacity(0.72)
        default:
            return base.mixed(with: .white, amount: 0.44).color
        }
    }
}

private struct RGB {
    let red: Double
    let green: Double
    let blue: Double

    static let white = RGB(red: 1, green: 1, blue: 1)
    static let black = RGB(red: 0, green: 0, blue: 0)

    init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    init(hex: String) {
        let sanitized = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: sanitized).scanHexInt64(&value)

        red = Double((value >> 16) & 0xFF) / 255.0
        green = Double((value >> 8) & 0xFF) / 255.0
        blue = Double(value & 0xFF) / 255.0
    }

    var color: Color {
        Color(red: red, green: green, blue: blue)
    }

    func mixed(with other: RGB, amount: Double) -> RGB {
        let clampedAmount = min(max(amount, 0), 1)
        let retainedAmount = 1 - clampedAmount

        return RGB(
            red: (red * retainedAmount) + (other.red * clampedAmount),
            green: (green * retainedAmount) + (other.green * clampedAmount),
            blue: (blue * retainedAmount) + (other.blue * clampedAmount)
        )
    }
}

private extension Color {
    init(hex: String) {
        let rgb = RGB(hex: hex)
        self.init(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }
}

struct TimetableView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            TimetableView(
                session: PreviewFactory.makeSession(state: .authenticated),
                client: PreviewTimetableClient.loaded()
            )
            .previewDisplayName("Timetable Loaded")

            TimetableView(
                session: PreviewFactory.makeSession(state: .authenticated),
                client: PreviewTimetableClient.loaded()
            )
            .preferredColorScheme(.dark)
            .previewDisplayName("Timetable Loaded - Dark")

            TimetableView(
                session: PreviewFactory.makeSession(state: .authenticated),
                client: PreviewTimetableClient(scenario: .loadedLongTitle)
            )
            .previewDisplayName("Timetable Loaded - Long Title")

            TimetableView(
                session: PreviewFactory.makeSession(state: .authenticated),
                client: PreviewTimetableClient(scenario: .empty)
            )
            .previewDisplayName("Timetable Empty")

            TimetableView(
                session: PreviewFactory.makeSession(state: .authenticated),
                client: PreviewTimetableClient.loaded()
            )
            .preferredColorScheme(.dark)
            .previewDisplayName("Timetable Loaded - Dark")

            TimetableCatalogSheetPreview()
                .previewDisplayName("Add Course Sheet")

            TimetableCatalogSheetPreview()
                .preferredColorScheme(.dark)
                .previewDisplayName("Add Course Sheet - Dark")

            TimetableCatalogSheetPreview(actionMessage: TimetableFailure.timeConflict.message)
                .previewDisplayName("Add Course Sheet - Conflict Banner")

            TimetableCatalogSheetPreview(actionMessage: TimetableFailure.duplicateLecture.message)
                .previewDisplayName("Add Course Sheet - Duplicate Banner")

            TimetableCatalogSheetPreview(errorMessage: TimetableFailure.network.message)
                .previewDisplayName("Add Course Sheet - Catalog Error")

            TimetableLectureDetailSheetPreview()
                .previewDisplayName("Course Detail - Remove")

            TimetableLectureDetailSheetPreview()
                .preferredColorScheme(.dark)
                .previewDisplayName("Course Detail - Remove - Dark")

            TimetableLectureDetailSheetPreview(isAdded: false, lecture: PreviewTimetableData.catalog[3])
                .previewDisplayName("Course Detail - Add")

            TimetableLectureDetailSheetPreview(lecture: PreviewTimetableData.currentLectures[0])
                .previewDisplayName("Course Detail - Multi Schedule")
        }
    }
}

private struct TimetableCatalogSheetPreview: View {
    @State private var filter: TimetableCatalogFilter = .all
    @State private var query = ""

    let errorMessage: String?
    let actionMessage: String?

    init(
        errorMessage: String? = nil,
        actionMessage: String? = nil
    ) {
        self.errorMessage = errorMessage
        self.actionMessage = actionMessage
    }

    var body: some View {
        TimetableCatalogSheet(
            lectures: PreviewTimetableData.catalog,
            filters: [.all, .memberMajor, .general],
            filter: $filter,
            query: $query,
            memberContext: PreviewTimetableData.memberContext,
            isLoading: false,
            errorMessage: errorMessage,
            actionMessage: actionMessage,
            focusSearchOnAppear: false,
            addedLectureIds: Set(PreviewTimetableData.currentLectures.map(\.id)),
            onClose: {},
            onDismissError: {},
            onDismissActionMessage: {},
            onAdd: { _ in },
            onRemove: { _ in }
        )
        .padding(.horizontal, 12)
        .background(AppTheme.backgroundTop)
    }
}

private struct TimetableLectureDetailSheetPreview: View {
    let isAdded: Bool
    let lecture: TimetableLectureItem

    init(
        isAdded: Bool = true,
        lecture: TimetableLectureItem = PreviewTimetableData.longTitleLectures[0]
    ) {
        self.isAdded = isAdded
        self.lecture = lecture
    }

    var body: some View {
        TimetableLectureDetailSheet(
            lecture: lecture,
            primaryActionTitle: isAdded ? "Remove from Timetable" : "Add to Timetable",
            primaryActionColor: isAdded ? Color(red: 0.94, green: 0.27, blue: 0.25) : AuthPalette.primaryStart,
            primaryActionConfirmationTitle: isAdded ? "Remove this course from your timetable?" : nil,
            onClose: {},
            onPrimaryAction: {}
        )
        .background(AppTheme.backgroundTop)
    }
}
