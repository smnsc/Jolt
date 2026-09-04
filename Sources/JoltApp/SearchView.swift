import AppKit
import JoltCore
import SwiftUI

private enum IssueListMetrics {
  static let outerHorizontalInset: CGFloat = 8
  static let contentHorizontalPadding: CGFloat = 8
  static let topPadding: CGFloat = 6

  static var rowInsets: EdgeInsets {
    EdgeInsets(
      top: 1,
      leading: outerHorizontalInset,
      bottom: 1,
      trailing: outerHorizontalInset
    )
  }
}

private enum IssueListScrollTarget: Hashable {
  case issue(String)
  case seeMoreResults
}

struct SearchView: View {
  @EnvironmentObject private var model: AppModel
  @EnvironmentObject private var preferences: AppPreferences
  @Environment(\.openSettings) private var openSettings

  var body: some View {
    VStack(spacing: 0) {
      header
      if !model.isIssuePreviewPresented, model.isAuthenticated, model.selectedSite != nil,
        !model.issues.isEmpty,
        preferences.scopeBarLayout != .off
      {
        SearchScopeBar()
          .environmentObject(model)
      }
      Divider()
      content
    }
    .safeAreaInset(edge: .bottom, spacing: 0) {
      if model.isAuthenticated, model.selectedSite != nil {
        SearchFooter()
          .environmentObject(model)
      }
    }
    // Let the root view fill the window's full-size content view. A fixed 560-point root is laid
    // out below the hidden title-bar safe area before ignoresSafeArea shifts it upward, leaving a
    // title-bar-sized gap beneath the footer.
    .frame(
      minWidth: SearchWindowMetrics.minimumSize.width,
      maxWidth: .infinity,
      minHeight: SearchWindowMetrics.minimumSize.height,
      maxHeight: .infinity
    )
    .ignoresSafeArea(.container, edges: .top)
    .background {
      SearchWindowBackground(mode: preferences.background)
        .ignoresSafeArea()
    }
    .overlay(alignment: .bottomTrailing) {
      if model.isActionsMenuPresented, model.selectedIssue != nil {
        IssueActionsMenu()
          .environmentObject(model)
          .padding(.trailing, 18)
          .padding(.bottom, 50)
          .transition(.move(edge: .bottom).combined(with: .opacity))
          .zIndex(200)
      }
    }
    .animation(.easeOut(duration: 0.14), value: model.isActionsMenuPresented)
    .background {
      if model.isIssuePreviewPresented {
        IssuePreviewKeyboardHandler()
          .environmentObject(model)
      }
    }
  }

  private var header: some View {
    HStack(spacing: 8) {
      if model.isIssuePreviewPresented {
        HeaderButton(
          systemName: "chevron.left",
          help: "Back to search results",
          action: model.dismissIssuePreview
        )
        Text(model.selectedIssue?.key ?? "Issue preview")
          .font(.headline)
          .foregroundStyle(.secondary)
        Spacer()
      } else if model.isAuthenticated {
        SearchField()
          .environmentObject(model)
          .layoutPriority(1)
      } else {
        Spacer()
      }
      HeaderButton(
        systemName: "scope",
        help: "Reset the Jolt window size and center it on this display",
        action: model.centerSearchWindow
      )
      HeaderButton(systemName: "gearshape", help: "Settings (⌘,)") {
        model.prepareToOpenSettings()
        openSettings()
      }
    }
    .padding(.horizontal, 14)
    .frame(height: 54)
    .background { WindowDragHandle() }
    .zIndex(20)
  }

  @ViewBuilder
  private var content: some View {
    if model.isIssuePreviewPresented, let issue = model.selectedIssue {
      IssuePreview(issue: issue)
    } else if !model.isAuthenticated {
      signInView
    } else if model.sites.count > 1 && model.selectedSite == nil {
      sitePickerView
    } else if model.issues.isEmpty && model.isLoading {
      ProgressView("Searching Jira…")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    } else if model.issues.isEmpty {
      ContentUnavailableView(
        "No Issues Found",
        systemImage: "magnifyingglass",
        description: Text(model.errorMessage ?? "Try different search terms.")
      )
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    } else {
      issueList
    }
  }

  private var signInView: some View {
    JiraConnectionView()
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .padding(24)
  }

  private var sitePickerView: some View {
    VStack(spacing: 14) {
      Text("Choose a Jira site")
        .font(.title2.bold())
      Text("You can change this later in Settings.")
        .foregroundStyle(.secondary)
      ForEach(model.sites) { site in
        Button {
          Task { await model.select(site: site) }
        } label: {
          HStack {
            Image(systemName: "building.2")
            VStack(alignment: .leading) {
              Text(site.name).fontWeight(.semibold)
              Text(site.url.host ?? site.url.absoluteString)
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
          }
          .frame(width: 360)
        }
        .buttonStyle(.bordered)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private var issueList: some View {
    ScrollViewReader { proxy in
      List {
        ForEach(model.issues) { issue in
          IssueRow(
            issue: issue,
            isSelected: model.selectedIssueID == issue.id,
            onSelect: { model.selectIssue(issue.id) },
            onOpenInBrowser: {
              model.selectIssue(issue.id)
              model.openSelectedIssue()
            },
            onPerformAction: { action in
              model.selectIssue(issue.id)
              model.performIssueAction(action)
            }
          )
          .id(IssueListScrollTarget.issue(issue.id))
          .listRowInsets(IssueListMetrics.rowInsets)
          .listRowBackground(Color.clear)
          .listRowSeparator(.hidden)
          .background {
            if issue.id == model.issues.first?.id {
              CompactListScrollerInstaller()
            }
          }
        }

        SeeMoreResultsRow(isSelected: model.isSeeMoreResultsSelected) {
          model.openCurrentSearchInJira()
        }
        .id(IssueListScrollTarget.seeMoreResults)
        .listRowInsets(IssueListMetrics.rowInsets)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
      }
      .listStyle(.plain)
      .scrollContentBackground(.hidden)
      .padding(.top, IssueListMetrics.topPadding)
      .onChange(of: model.selectedIssueID) { _, selectedIssueID in
        guard let selectedIssueID else { return }
        proxy.scrollTo(IssueListScrollTarget.issue(selectedIssueID))
      }
      .onChange(of: model.isSeeMoreResultsSelected) { _, isSelected in
        guard isSelected else { return }
        proxy.scrollTo(IssueListScrollTarget.seeMoreResults)
      }
    }
  }
}

private struct SeeMoreResultsRow: View {
  let isSelected: Bool
  let action: () -> Void
  @State private var isHovered = false

  var body: some View {
    Button(action: action) {
      HStack(spacing: 10) {
        Image(systemName: "safari")
          .font(.system(size: 15, weight: .medium))
          .frame(width: 20, height: 20)
        Text("See more results in Jira")
          .font(.system(size: 15, weight: .semibold))
        Spacer()
        Image(systemName: "arrow.up.right")
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(.secondary)
      }
      .padding(.vertical, 7)
      .padding(.horizontal, IssueListMetrics.contentHorizontalPadding)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .background {
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .fill(rowFill)
        .overlay {
          RoundedRectangle(cornerRadius: 8, style: .continuous)
            .strokeBorder(
              isSelected ? Color.accentColor.opacity(0.42) : Color.clear,
              lineWidth: 1
            )
        }
    }
    .onHover { hovering in
      withAnimation(.easeOut(duration: 0.12)) {
        isHovered = hovering
      }
    }
    .help("Open this search in Jira")
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }

  private var rowFill: Color {
    if isSelected {
      return Color.accentColor.opacity(0.14)
    }
    if isHovered {
      return Color.primary.opacity(0.065)
    }
    return .clear
  }
}

private struct SearchScopeBar: View {
  @EnvironmentObject private var model: AppModel
  @EnvironmentObject private var preferences: AppPreferences

  var body: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 7) {
        scopeChoices
      }
      .padding(.horizontal, 14)
    }
    .frame(height: 42)
    .background(Color(nsColor: .controlBackgroundColor).opacity(0.22))
  }

  @ViewBuilder
  private var scopeChoices: some View {
    switch preferences.scopeBarLayout {
    case .rankedByFrequency:
      ForEach(rankedScopes) { scope in
        ScopePill(
          title: scope.title,
          isSelected: isActive(scope),
          accessibilityLabel: accessibilityLabel(for: scope)
        ) {
          toggle(scope)
        }
        .help(scopeHelp(for: scope))
      }
    case .groupedByKind:
      groupedScopeChoices
    case .off:
      EmptyView()
    }
  }

  @ViewBuilder
  private var groupedScopeChoices: some View {
    Group {
        scopeLabel("Project", systemName: "building.2")
        ForEach(model.availableProjectScopes) { project in
          ScopePill(
            title: project.key,
            isSelected: model.isProjectScopeActive(project),
            accessibilityLabel: "Add project \(project.key) to the query"
          ) {
            model.toggleProjectScope(project)
          }
        }

        scopeDivider
        scopeLabel("Issue Type", systemName: "square.stack.3d.up")
        ForEach(model.availableIssueTypeScopes) { issueType in
          ScopePill(
            title: issueType.name,
            isSelected: model.isIssueTypeScopeActive(issueType),
            accessibilityLabel: "Add issue type \(issueType.name) to the query"
          ) {
            model.toggleIssueTypeScope(issueType)
          }
        }
    }
  }

  private var rankedScopes: [RankedSearchScope] {
    var projectCounts: [JiraProject: Int] = [:]
    var issueTypeCounts: [String: (issueType: JiraIssueType, count: Int)] = [:]

    for issue in model.issues {
      projectCounts[issue.project, default: 0] += 1

      let nameKey = normalized(issue.issueType.name)
      if let current = issueTypeCounts[nameKey] {
        issueTypeCounts[nameKey] = (current.issueType, current.count + 1)
      } else {
        issueTypeCounts[nameKey] = (issue.issueType, 1)
      }
    }

    let projects = projectCounts.map { project, count in
      RankedSearchScope(
        id: "project:\(project.id)",
        title: project.key,
        count: count,
        value: .project(project)
      )
    }
    let issueTypes = issueTypeCounts.map { nameKey, value in
      RankedSearchScope(
        id: "issueType:\(nameKey)",
        title: value.issueType.name,
        count: value.count,
        value: .issueType(value.issueType)
      )
    }

    return (projects + issueTypes).sorted { lhs, rhs in
      if lhs.count != rhs.count { return lhs.count > rhs.count }
      let titleOrder = lhs.title.localizedCaseInsensitiveCompare(rhs.title)
      if titleOrder != .orderedSame { return titleOrder == .orderedAscending }
      return lhs.id < rhs.id
    }
  }

  private func isActive(_ scope: RankedSearchScope) -> Bool {
    switch scope.value {
    case .project(let project): return model.isProjectScopeActive(project)
    case .issueType(let issueType): return model.isIssueTypeScopeActive(issueType)
    }
  }

  private func toggle(_ scope: RankedSearchScope) {
    switch scope.value {
    case .project(let project): model.toggleProjectScope(project)
    case .issueType(let issueType): model.toggleIssueTypeScope(issueType)
    }
  }

  private func accessibilityLabel(for scope: RankedSearchScope) -> String {
    switch scope.value {
    case .project:
      return "Add project \(scope.title) to the query, \(scope.count) issues"
    case .issueType:
      return "Add issue type \(scope.title) to the query, \(scope.count) issues"
    }
  }

  private func scopeHelp(for scope: RankedSearchScope) -> String {
    let kind = switch scope.value {
    case .project: "Project"
    case .issueType: "Issue Type"
    }
    return "\(kind) · \(scope.count) \(scope.count == 1 ? "issue" : "issues")"
  }

  private func normalized(_ value: String) -> String {
    value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
  }

  private var scopeDivider: some View {
    Divider()
      .frame(height: 18)
      .padding(.horizontal, 2)
  }

  private func scopeLabel(_ title: String, systemName: String) -> some View {
    Label(title, systemImage: systemName)
      .font(.caption.weight(.medium))
      .foregroundStyle(.secondary)
      .fixedSize()
  }
}

private struct RankedSearchScope: Identifiable {
  enum Value {
    case project(JiraProject)
    case issueType(JiraIssueType)
  }

  let id: String
  let title: String
  let count: Int
  let value: Value
}

private struct ScopePill: View {
  let title: String
  let isSelected: Bool
  let accessibilityLabel: String
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Text(title)
        .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
        .lineLimit(1)
        .padding(.horizontal, 11)
        .padding(.vertical, 5)
        .background {
          Capsule(style: .continuous)
            .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.055))
        }
        .overlay {
          Capsule(style: .continuous)
            .strokeBorder(
              isSelected ? Color.accentColor.opacity(0.5) : Color.primary.opacity(0.08),
              lineWidth: 1
            )
        }
        .contentShape(Capsule())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(accessibilityLabel)
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }
}

private struct SearchFooter: View {
  @EnvironmentObject private var model: AppModel

  var body: some View {
    VStack(spacing: 0) {
      Divider()
      footerContent
    }
    .fixedSize(horizontal: false, vertical: true)
    .background {
      ZStack {
        Rectangle().fill(.regularMaterial)
        Color(nsColor: .windowBackgroundColor).opacity(0.16)
      }
    }
    .background { WindowDragHandle() }
  }

  private var footerContent: some View {
    HStack {
      if let site = model.selectedSite {
        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        Text(site.name).foregroundStyle(.secondary)
      } else {
        Text("Jolt").foregroundStyle(.secondary)
      }
      if let error = model.errorMessage, !model.issues.isEmpty {
        Text("•").foregroundStyle(.tertiary)
        Text(error).foregroundStyle(.red).lineLimit(1)
      }
      Spacer()
      if model.selectedIssue != nil {
        if model.isIssuePreviewPresented {
          FooterActionButton(title: "Back to Results", shortcut: "←") {
            model.dismissIssuePreview()
          }
        } else {
          FooterActionButton(title: "Quick Look Issue", shortcut: "→") {
            model.presentIssuePreview()
          }
        }
        FooterActionButton(title: "Open in Browser", shortcut: "↩") {
          model.openSelectedIssue()
        }
        FooterActionButton(title: "Actions", shortcut: "⌥ ↩") {
          if model.isActionsMenuPresented {
            model.dismissActionsMenu()
          } else {
            model.presentActionsMenu()
          }
        }
      }
    }
    .font(.callout)
    .padding(.horizontal, 18)
    .frame(height: 42)
  }
}

private struct FooterActionButton: View {
  let title: String
  let shortcut: String
  let action: () -> Void
  @State private var isHovered = false

  var body: some View {
    Button(action: action) {
      HStack(spacing: 7) {
        Text(title)
          .fontWeight(.semibold)
        KeyboardShortcutBadge(label: shortcut)
      }
      .padding(.horizontal, 8)
      .padding(.vertical, 5)
      .background(
        isHovered ? Color.primary.opacity(0.085) : Color.clear,
        in: RoundedRectangle(cornerRadius: 7, style: .continuous)
      )
      .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
    .buttonStyle(.plain)
    .onHover { hovering in
      withAnimation(.easeOut(duration: 0.12)) {
        isHovered = hovering
      }
    }
    .help(title)
  }
}

private struct KeyboardShortcutBadge: View {
  let label: String

  var body: some View {
    Text(label)
      .font(.system(size: 12, weight: .medium, design: .rounded))
      .foregroundStyle(.secondary)
      .padding(.horizontal, 7)
      .padding(.vertical, 3)
      .background(.quaternary, in: RoundedRectangle(cornerRadius: 5))
  }
}

private struct IssueActionsMenu: View {
  @EnvironmentObject private var model: AppModel

  var body: some View {
    VStack(alignment: .leading, spacing: 5) {
      if let issue = model.selectedIssue {
        Text(issue.key)
          .font(.headline)
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .padding(.horizontal, 10)
          .padding(.top, 6)
          .padding(.bottom, 3)
      }

      ForEach(IssueAction.allCases) { action in
        actionRow(action)
      }
    }
    .padding(7)
    .frame(width: 320)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .strokeBorder(Color(nsColor: .separatorColor).opacity(0.55))
    }
    .shadow(color: .black.opacity(0.22), radius: 18, y: 7)
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Issue actions")
  }

  private func actionRow(_ action: IssueAction) -> some View {
    let isSelected = model.selectedIssueActionIndex == action.rawValue
    return Button {
      model.performIssueAction(action)
    } label: {
      HStack(spacing: 11) {
        Image(systemName: action.systemImage)
          .font(.system(size: 16, weight: .medium))
          .frame(width: 20)
        Text(action.title)
          .font(.system(size: 15, weight: .medium))
        Spacer()
        if isSelected {
          KeyboardShortcutBadge(label: "↩")
        }
      }
      .padding(.horizontal, 10)
      .frame(height: 40)
      .background(
        isSelected ? Color.accentColor.opacity(0.18) : Color.clear,
        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
      )
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .onHover { hovering in
      if hovering { model.selectIssueAction(action) }
    }
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }
}

private struct HeaderButton: View {
  let systemName: String
  let help: String
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Image(systemName: systemName)
        .font(.system(size: 16, weight: .medium))
        .frame(width: 34, height: 34)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .help(help)
  }
}

private struct WindowDragHandle: NSViewRepresentable {
  func makeNSView(context: Context) -> NSView {
    DraggableView()
  }

  func updateNSView(_ nsView: NSView, context: Context) {}

  private final class DraggableView: NSView {
    override func mouseDown(with event: NSEvent) {
      window?.performDrag(with: event)
      if window?.isKeyWindow == true {
        NotificationCenter.default.post(name: .focusSearchField, object: nil)
      }
    }
  }
}

/// Keeps the system scroll behavior and hit target while giving result lists a quieter,
/// Raycast-like visual indicator.
private struct CompactListScrollerInstaller: NSViewRepresentable {
  func makeNSView(context: Context) -> NSView {
    ScrollViewProbe()
  }

  func updateNSView(_ nsView: NSView, context: Context) {
    (nsView as? ScrollViewProbe)?.installScroller()
  }

  private final class ScrollViewProbe: NSView {
    private weak var configuredScrollView: NSScrollView?
    private var installationScheduled = false

    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      installScroller()
    }

    override func viewDidMoveToSuperview() {
      super.viewDidMoveToSuperview()
      configuredScrollView = nil
      installScroller()
    }

    override func layout() {
      super.layout()
      installScroller()
    }

    func installScroller() {
      guard !installationScheduled, configuredScrollView !== enclosingScrollView else { return }
      installationScheduled = true

      DispatchQueue.main.async { [weak self] in
        guard let self else { return }
        installationScheduled = false
        guard let scrollView = enclosingScrollView else { return }

        // Match macOS from the first layout. Forcing the overlay style here could briefly render
        // its collapsed, hairline-width presentation before AppKit restored the user's preferred
        // scrollbar style on the next window activation.
        scrollView.scrollerStyle = NSScroller.preferredScrollerStyle
        if !(scrollView.verticalScroller is CompactOverlayScroller) {
          let scroller = CompactOverlayScroller()
          scroller.controlSize = .small
          scroller.knobStyle = scrollView.verticalScroller?.knobStyle ?? .default
          scrollView.verticalScroller = scroller
        }

        // A freshly installed NSScroller starts with no useful knob proportion. Reflect the
        // completed list geometry immediately so the first results display does not show the
        // minimum-size knob until the window next becomes active.
        scrollView.tile()
        scrollView.layoutSubtreeIfNeeded()
        scrollView.reflectScrolledClipView(scrollView.contentView)
        scrollView.verticalScroller?.needsDisplay = true
        configuredScrollView = scrollView
      }
    }
  }

  private final class CompactOverlayScroller: NSScroller {
    override class var isCompatibleWithOverlayScrollers: Bool {
      self == CompactOverlayScroller.self
    }

    override func drawKnob() {
      let systemKnobRect = rect(for: .knob)
      guard systemKnobRect.height > 0 else { return }

      let indicatorWidth: CGFloat = 4
      let horizontalInset: CGFloat = 3
      let verticalInset: CGFloat = 1
      let indicatorRect = NSRect(
        x: systemKnobRect.maxX - indicatorWidth - horizontalInset,
        y: systemKnobRect.minY + verticalInset,
        width: indicatorWidth,
        height: max(8, systemKnobRect.height - (verticalInset * 2))
      )

      NSColor.tertiaryLabelColor.withAlphaComponent(0.72).setFill()
      NSBezierPath(
        roundedRect: indicatorRect,
        xRadius: indicatorWidth / 2,
        yRadius: indicatorWidth / 2
      ).fill()
    }

    override func drawKnobSlot(in slotRect: NSRect, highlight flag: Bool) {}
  }
}

private struct SearchWindowBackground: View {
  let mode: BackgroundMode

  @ViewBuilder
  var body: some View {
    switch mode {
    case .opaque:
      Color(nsColor: .windowBackgroundColor)
    case .tinted:
      HUDBackground()
    case .clear:
      if #available(macOS 26.0, *) {
        LiquidGlassBackground(style: .regular)
      } else {
        Rectangle().fill(.regularMaterial)
      }
    }
  }
}

private struct HUDBackground: View {
  var body: some View {
    HUDVisualEffectBackground()
      // The HUD material deliberately darkens content behind a light window. Keep its stronger
      // blur, but lift the surface back toward the active appearance's window background color.
      .overlay(Color(nsColor: .windowBackgroundColor).opacity(0.34))
  }
}

@available(macOS 26.0, *)
private struct LiquidGlassBackground: View {
  let style: Glass

  var body: some View {
    Color.clear
      .glassEffect(style, in: Rectangle())
  }
}

private struct HUDVisualEffectBackground: NSViewRepresentable {
  func makeNSView(context: Context) -> NSVisualEffectView {
    let view = NSVisualEffectView()
    configure(view)
    return view
  }

  func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
    configure(nsView)
  }

  private func configure(_ view: NSVisualEffectView) {
    view.material = .hudWindow
    view.blendingMode = .behindWindow
    view.state = .active
    view.isEmphasized = true
  }
}

private struct IssueRow: View {
  @EnvironmentObject private var images: ImageRepository
  let issue: JiraIssue
  let isSelected: Bool
  let onSelect: () -> Void
  let onOpenInBrowser: () -> Void
  let onPerformAction: (IssueAction) -> Void
  @State private var isHovered = false

  var body: some View {
    Button {
      if isSelected {
        onOpenInBrowser()
      } else {
        onSelect()
      }
    } label: {
      HStack(spacing: 10) {
        IssueTypeImage(url: issue.issueType.iconURL)
          .environmentObject(images)
        Text(issue.summary)
          .font(.system(size: 15, weight: .regular))
          .lineLimit(1)
        Text("\(issue.key) · \(issue.issueType.name)")
          .foregroundStyle(.secondary)
          .lineLimit(1)
        Spacer(minLength: 12)
        StatusPill(status: issue.status)
      }
      .padding(.vertical, 7)
      .padding(.horizontal, IssueListMetrics.contentHorizontalPadding)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .background { rowBackground }
    .onHover { hovering in
      withAnimation(.easeOut(duration: 0.12)) {
        isHovered = hovering
      }
    }
    .contextMenu {
      ForEach(IssueAction.allCases) { action in
        Button {
          onPerformAction(action)
        } label: {
          Label(action.title, systemImage: action.systemImage)
        }
      }
    }
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }

  private var rowBackground: some View {
    RoundedRectangle(cornerRadius: 8, style: .continuous)
      .fill(rowFill)
      .overlay {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .strokeBorder(
            isSelected ? Color.accentColor.opacity(0.42) : Color.clear,
            lineWidth: 1
          )
      }
  }

  private var rowFill: Color {
    if isSelected {
      return Color.accentColor.opacity(0.14)
    }
    if isHovered {
      return Color.primary.opacity(0.065)
    }
    return .clear
  }
}

private struct IssuePreview: View {
  let issue: JiraIssue

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        Text(issue.summary)
          .font(.system(size: 26, weight: .bold))
          .textSelection(.enabled)

        Divider()

        if let description = issue.description, !description.isEmpty {
          Text(description)
            .font(.system(size: 15))
            .lineSpacing(5)
            .textSelection(.enabled)
        } else {
          ContentUnavailableView(
            "No Description",
            systemImage: "doc.text",
            description: Text("This Jira issue does not have a description.")
          )
          .frame(maxWidth: .infinity, minHeight: 220)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, 28)
      .padding(.vertical, 24)
    }
  }
}

private struct IssuePreviewKeyboardHandler: NSViewRepresentable {
  @EnvironmentObject private var model: AppModel

  func makeCoordinator() -> Coordinator {
    Coordinator(model: model)
  }

  func makeNSView(context: Context) -> NSView {
    context.coordinator.installMonitor()
    return NSView(frame: .zero)
  }

  func updateNSView(_ nsView: NSView, context: Context) {
    context.coordinator.model = model
  }

  static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
    coordinator.removeMonitor()
  }

  @MainActor
  final class Coordinator {
    var model: AppModel
    private var monitor: Any?

    init(model: AppModel) {
      self.model = model
    }

    func installMonitor() {
      guard monitor == nil else { return }
      monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
        guard let self, model.isIssuePreviewPresented else { return event }

        if model.isActionsMenuPresented {
          switch event.keyCode {
          case 125:
            model.moveIssueAction(by: 1)
            return nil
          case 126:
            model.moveIssueAction(by: -1)
            return nil
          case 36:
            model.performSelectedIssueAction()
            return nil
          case 53:
            model.dismissActionsMenu()
            return nil
          default:
            return event
          }
        }

        switch event.keyCode {
        case 123, 51, 53:
          model.dismissIssuePreview()
          return nil
        case 36 where event.modifierFlags.contains(.option):
          model.presentActionsMenu()
          return nil
        case 36:
          model.openSelectedIssue()
          return nil
        default:
          return event
        }
      }
    }

    func removeMonitor() {
      if let monitor {
        NSEvent.removeMonitor(monitor)
        self.monitor = nil
      }
    }
  }
}

private struct IssueTypeImage: View {
  @EnvironmentObject private var images: ImageRepository
  let url: URL?
  @State private var image: NSImage?

  var body: some View {
    Group {
      if let image {
        Image(nsImage: image).resizable().scaledToFit()
      } else {
        Image(systemName: "square.fill").foregroundStyle(.blue)
      }
    }
    .frame(width: 18, height: 18)
    .frame(width: 20, height: 20)
    .task(id: url) {
      guard let url else { return }
      image = await images.image(for: url)
    }
  }
}

private struct StatusPill: View {
  let status: JiraStatus

  var body: some View {
    HStack(spacing: 6) {
      Image(systemName: icon)
        .foregroundStyle(tint)
      Text(status.name)
        .foregroundStyle(.primary)
    }
    .font(.system(size: 12, weight: .medium))
    .padding(.horizontal, 9)
    .padding(.vertical, 5)
    .background {
      RoundedRectangle(cornerRadius: 6, style: .continuous)
        .fill(Color(nsColor: .controlBackgroundColor).opacity(0.94))
        .overlay {
          RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(tint.opacity(0.16))
        }
    }
    .lineLimit(1)
    .fixedSize(horizontal: true, vertical: false)
    .accessibilityElement(children: .combine)
  }

  private var icon: String {
    switch status.category {
    case .done: return "checkmark"
    case .indeterminate: return "arrow.clockwise"
    case .new: return "circle"
    case .unknown: return "questionmark"
    }
  }

  private var tint: Color {
    switch status.category {
    case .done: return Color(nsColor: .systemGreen)
    case .indeterminate: return Color(nsColor: .systemBlue)
    case .new: return Color(nsColor: .systemGray)
    case .unknown: return Color(nsColor: .systemOrange)
    }
  }
}
