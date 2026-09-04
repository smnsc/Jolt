import AppKit
import Combine
import Foundation
import JoltCore

struct AutocompleteContext: Equatable {
  let kind: SearchShortcutKind
  let query: String
}

enum SearchWindowMetrics {
  static let defaultSize = NSSize(width: 900, height: 560)
  static let minimumSize = NSSize(width: 640, height: 400)
}

@MainActor
final class AppModel: ObservableObject {
  static let shared = AppModel()

  @Published var input = ""
  @Published private(set) var issues: [JiraIssue] = []
  @Published var selectedIssueID: String?
  @Published private(set) var isSearching = false
  @Published private(set) var isConnecting = false
  @Published private(set) var isAuthenticated = false
  @Published private(set) var sites: [JiraSite] = []
  @Published var selectedSite: JiraSite?
  @Published var errorMessage: String?
  @Published var autocompleteContext: AutocompleteContext?
  @Published private(set) var autocompleteSuggestions: [ResolvedShortcut] = []
  @Published var autocompleteSelection = 0
  @Published private(set) var isActionsMenuPresented = false
  @Published private(set) var selectedIssueActionIndex = 0
  @Published private(set) var isIssuePreviewPresented = false
  @Published private(set) var isSeeMoreResultsSelected = false

  let preferences = AppPreferences.shared
  let auth: JiraAuthSession
  let client: JiraClient
  let cache: CacheManager
  let metadata: JiraMetadataStore
  let images: ImageRepository

  private var searchTask: Task<Void, Never>?
  private var autocompleteTask: Task<Void, Never>?
  private var connectionTask: Task<Void, Never>?
  private weak var searchWindow: NSWindow?
  private var searchWindowDidResignKeyObserver: NSObjectProtocol?
  private var searchWindowDidBecomeKeyObserver: NSObjectProtocol?
  private var searchWindowFocusTask: Task<Void, Never>?
  private var displayedJQL: String?

  var isLoading: Bool { isSearching || isConnecting }

  var selectedIssue: JiraIssue? {
    issues.first(where: { $0.id == selectedIssueID })
  }

  var availableProjectScopes: [JiraProject] {
    uniqueValues(issues.map(\.project)).sorted {
      $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
    }
  }

  var availableIssueTypeScopes: [JiraIssueType] {
    uniqueIssueTypesByName(issues.map(\.issueType)).sorted {
      $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
    }
  }

  private init() {
    let auth = JiraAuthSession()
    let client = JiraClient(auth: auth)
    let cache = CacheManager.shared
    self.auth = auth
    self.client = client
    self.cache = cache
    self.metadata = JiraMetadataStore(client: client, cache: cache)
    self.images = ImageRepository(client: client, cache: cache)
  }

  func start() {
    Task {
      isAuthenticated = await auth.isAuthenticated
      guard isAuthenticated, let site = await auth.site else { return }
      sites = [site]
      await select(site: site)
    }
  }

  func connect(siteURL: String, email: String, apiKey: String) {
    guard connectionTask == nil else { return }
    errorMessage = nil
    isConnecting = true
    connectionTask = Task {
      defer {
        isConnecting = false
        connectionTask = nil
      }
      do {
        let site = try await auth.connect(siteURL: siteURL, email: email, apiKey: apiKey)
        sites = [site]
        isAuthenticated = true
        await select(site: site)
      } catch is CancellationError {
        return
      } catch {
        errorMessage = error.userFacingMessage
      }
    }
  }

  func cancelConnection() {
    connectionTask?.cancel()
  }

  func select(site: JiraSite) async {
    let isChangingSite = selectedSite?.id != site.id
    if isChangingSite {
      searchTask?.cancel()
      autocompleteTask?.cancel()
      issues = []
      selectedIssueID = nil
      isSeeMoreResultsSelected = false
      displayedJQL = nil
      isIssuePreviewPresented = false
      input = ""
      updateAutocomplete(nil)
    }
    selectedSite = site
    preferences.selectedSite = site
    await client.setSite(site)
    isSearching = true
    do {
      try await metadata.load(siteID: site.id)
      scheduleSearch(immediate: true)
    } catch {
      isSearching = false
      errorMessage = error.userFacingMessage
    }
  }

  func logout() {
    connectionTask?.cancel()
    searchTask?.cancel()
    autocompleteTask?.cancel()
    Task {
      do { try await auth.logout() } catch { errorMessage = error.userFacingMessage }
      isAuthenticated = false
      await metadata.clearMemory()
      await clearCachedData()
      sites = []
      selectedSite = nil
      preferences.selectedSite = nil
      issues = []
      selectedIssueID = nil
      isSeeMoreResultsSelected = false
      displayedJQL = nil
      isIssuePreviewPresented = false
      input = ""
    }
  }

  func clearCachedData() async {
    searchTask?.cancel()
    isSearching = false
    issues = []
    selectedIssueID = nil
    isSeeMoreResultsSelected = false
    displayedJQL = nil
    isIssuePreviewPresented = false
    images.clearMemory()
    await metadata.clearMemory()
    do {
      try await cache.clear()
      if isAuthenticated, let siteID = selectedSite?.id {
        try await metadata.load(siteID: siteID, force: true)
      }
    } catch {
      errorMessage = error.userFacingMessage
    }
  }

  func cachedDataByteCount() async -> Int64 {
    do {
      return try await cache.diskUsage()
    } catch {
      errorMessage = error.userFacingMessage
      return 0
    }
  }

  func cacheDirectoryURL() async throws -> URL {
    try await cache.directoryURL()
  }

  func inputDidChange(_ input: String) {
    dismissActionsMenu()
    dismissIssuePreview()
    if isSeeMoreResultsSelected {
      isSeeMoreResultsSelected = false
      selectedIssueID = issues.first?.id
    }
    self.input = input
    scheduleSearch()
  }

  func handleSearchEscape() {
    guard input.isEmpty else {
      updateAutocomplete(nil)
      inputDidChange("")
      restoreSearchFieldFocus()
      return
    }

    hideSearchWindow()
  }

  func scheduleSearch(immediate: Bool = false) {
    searchTask?.cancel()
    guard isAuthenticated, selectedSite != nil else { return }
    let scheduledInput = input
    let scheduledResultLimit = preferences.searchResultLimit.rawValue
    searchTask = Task {
      if !immediate {
        try? await Task.sleep(for: .milliseconds(250))
      }
      guard !Task.isCancelled else {
        isSearching = false
        return
      }
      do {
        let resolvedInput = await resolvingShortcuts(in: scheduledInput)
        guard !Task.isCancelled, input == scheduledInput else { return }
        let jql = try JQLBuilder().build(parsed: resolvedInput)
        isSearching = true
        errorMessage = nil
        let result = try await client.search(jql: jql, maxResults: scheduledResultLimit)
        guard !Task.isCancelled else {
          isSearching = false
          return
        }
        issues = result
        displayedJQL = jql
        reconcileSelectedIssue()
      } catch is CancellationError {
        isSearching = false
        return
      } catch {
        guard !Task.isCancelled else {
          isSearching = false
          return
        }
        errorMessage = error.userFacingMessage
      }
      isSearching = false
    }
  }

  func updateAutocomplete(_ context: AutocompleteContext?) {
    autocompleteContext = context
    autocompleteSelection = 0
    autocompleteTask?.cancel()
    guard let context, isAuthenticated else {
      autocompleteSuggestions = []
      return
    }
    autocompleteTask = Task {
      if context.kind == .assignee { try? await Task.sleep(for: .milliseconds(180)) }
      guard !Task.isCancelled else { return }
      do {
        let suggestions = try await metadata.suggestions(kind: context.kind, query: context.query)
        guard !Task.isCancelled, autocompleteContext == context else { return }
        autocompleteSuggestions = suggestions
      } catch {
        autocompleteSuggestions = []
      }
    }
  }

  private func resolvingShortcuts(in text: String) async -> ParsedSearch {
    var parsed = SearchQueryParser().parse(text)
    let shortcuts = parsed.unresolvedShortcuts
    parsed.unresolvedShortcuts = []

    for shortcut in shortcuts {
      guard
        let resolved = try? await metadata.exactShortcuts(
          kind: shortcut.kind,
          value: shortcut.value
        ), !resolved.isEmpty
      else {
        parsed.unresolvedShortcuts.append(shortcut)
        continue
      }

      switch shortcut.kind {
      case .project: parsed.projects.append(contentsOf: resolved)
      case .issueType: parsed.issueTypes.append(contentsOf: resolved)
      case .assignee: parsed.assignees.append(contentsOf: resolved)
      }
    }

    return parsed
  }

  func moveResult(by offset: Int) {
    guard !issues.isEmpty else { return }
    let seeMoreIndex = issues.count
    let current = isSeeMoreResultsSelected
      ? seeMoreIndex
      : issues.firstIndex(where: { $0.id == selectedIssueID }) ?? 0
    let destination = min(max(current + offset, 0), seeMoreIndex)
    if destination == seeMoreIndex {
      selectedIssueID = nil
      isSeeMoreResultsSelected = true
    } else {
      selectedIssueID = issues[destination].id
      isSeeMoreResultsSelected = false
    }
  }

  func selectIssue(_ id: String) {
    dismissActionsMenu()
    selectedIssueID = id
    isSeeMoreResultsSelected = false
    restoreSearchFieldFocus()
  }

  func presentIssuePreview() {
    guard selectedIssue != nil else { return }
    updateAutocomplete(nil)
    dismissActionsMenu()
    isIssuePreviewPresented = true
  }

  func dismissIssuePreview() {
    guard isIssuePreviewPresented else { return }
    dismissActionsMenu()
    isIssuePreviewPresented = false
    restoreSearchFieldFocus()
  }

  func openSelectedIssue() {
    if isSeeMoreResultsSelected {
      openCurrentSearchInJira()
      return
    }
    guard let issue = selectedIssue, let url = issueURL(for: issue) else { return }
    NSWorkspace.shared.open(url)
    dismissActionsMenu()
    hideSearchWindow()
  }

  func presentActionsMenu() {
    guard selectedIssue != nil else { return }
    updateAutocomplete(nil)
    selectedIssueActionIndex = 0
    isActionsMenuPresented = true
  }

  func dismissActionsMenu() {
    isActionsMenuPresented = false
  }

  func selectIssueAction(_ action: IssueAction) {
    selectedIssueActionIndex = action.rawValue
  }

  func moveIssueAction(by offset: Int) {
    let lastIndex = IssueAction.allCases.count - 1
    selectedIssueActionIndex = min(max(selectedIssueActionIndex + offset, 0), lastIndex)
  }

  func performSelectedIssueAction() {
    guard let action = IssueAction(rawValue: selectedIssueActionIndex) else { return }
    performIssueAction(action)
  }

  func performIssueAction(_ action: IssueAction) {
    switch action {
    case .openInBrowser:
      openSelectedIssue()
    case .copyKeyAndTitle:
      copySelectedIssue(includeHTMLLink: false)
    case .copyHTMLLink:
      copySelectedIssue(includeHTMLLink: true)
    }
  }

  private func copySelectedIssue(includeHTMLLink: Bool) {
    guard let issue = selectedIssue else { return }
    let formatter = IssueReferenceFormatter()
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()

    if includeHTMLLink, let url = issueURL(for: issue) {
      let item = NSPasteboardItem()
      item.setString(formatter.htmlLink(for: issue, url: url), forType: .html)
      item.setString(formatter.plainText(for: issue), forType: .string)
      pasteboard.writeObjects([item])
    } else {
      pasteboard.setString(formatter.plainText(for: issue), forType: .string)
    }

    dismissActionsMenu()
    hideSearchWindow()
  }

  private func issueURL(for issue: JiraIssue) -> URL? {
    guard let site = selectedSite else { return nil }
    return URL(string: "/browse/\(issue.key)", relativeTo: site.url)?.absoluteURL
  }

  func openCurrentSearchInJira() {
    guard let site = selectedSite, let displayedJQL else { return }
    var components = URLComponents(
      url: site.url.appendingPathComponent("issues"),
      resolvingAgainstBaseURL: false
    )
    components?.queryItems = [URLQueryItem(name: "jql", value: displayedJQL)]
    guard let url = components?.url else { return }
    NSWorkspace.shared.open(url)
    hideSearchWindow()
  }

  func toggleProjectScope(_ project: JiraProject) {
    let editor = SearchQueryScopeEditor()
    let aliases = [project.key, project.name]
    let updated: String
    if editor.contains(kind: .project, values: aliases, in: input) {
      updated = editor.removing(kind: .project, values: aliases, from: input)
    } else {
      updated = editor.adding(
        kind: .project,
        value: project.key.lowercased(),
        aliases: [project.name],
        to: input
      )
    }
    applyScopeQuery(updated)
  }

  func toggleIssueTypeScope(_ issueType: JiraIssueType) {
    let editor = SearchQueryScopeEditor()
    let updated: String
    if editor.contains(kind: .issueType, values: [issueType.name], in: input) {
      updated = editor.removing(kind: .issueType, values: [issueType.name], from: input)
    } else {
      updated = editor.adding(kind: .issueType, value: issueType.name, to: input)
    }
    applyScopeQuery(updated)
  }

  func isProjectScopeActive(_ project: JiraProject) -> Bool {
    SearchQueryScopeEditor().contains(
      kind: .project,
      values: [project.key, project.name],
      in: input
    )
  }

  func isIssueTypeScopeActive(_ issueType: JiraIssueType) -> Bool {
    SearchQueryScopeEditor().contains(kind: .issueType, values: [issueType.name], in: input)
  }

  func register(searchWindow: NSWindow) {
    let isNewWindow = self.searchWindow !== searchWindow
    self.searchWindow = searchWindow
    // WindowAccessor is updated whenever SwiftUI refreshes the search view, including after each
    // keystroke. Reapplying size constraints during those refreshes makes AppKit adjust the frame
    // repeatedly, which causes the window to drift on screen.
    guard isNewWindow else { return }

    searchWindow.styleMask.insert([.fullSizeContentView, .resizable])
    searchWindow.minSize = SearchWindowMetrics.minimumSize
    searchWindow.maxSize = NSSize(
      width: CGFloat.greatestFiniteMagnitude,
      height: CGFloat.greatestFiniteMagnitude
    )
    enforceSearchWindowSize(searchWindow)

    if let searchWindowDidResignKeyObserver {
      NotificationCenter.default.removeObserver(searchWindowDidResignKeyObserver)
    }
    if let searchWindowDidBecomeKeyObserver {
      NotificationCenter.default.removeObserver(searchWindowDidBecomeKeyObserver)
    }

    searchWindow.level = .floating
    searchWindow.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    searchWindow.isReleasedWhenClosed = false
    // SwiftUI's hidden-title-bar window remains titled underneath its custom chrome. Do not
    // remove that style: borderless windows cannot reliably become key again after orderOut.
    // Make the content view occupy the title-bar region as well, so the custom 560-point surface
    // does not leave a title-bar-sized strip below it.
    searchWindow.titleVisibility = .hidden
    searchWindow.titlebarAppearsTransparent = true
    searchWindow.isMovable = true
    searchWindow.isMovableByWindowBackground = true
    searchWindow.isOpaque = false
    searchWindow.backgroundColor = .clear
    searchWindow.hasShadow = true
    searchWindow.standardWindowButton(.closeButton)?.isHidden = true
    searchWindow.standardWindowButton(.zoomButton)?.isHidden = true
    searchWindow.standardWindowButton(.miniaturizeButton)?.isHidden = true

    searchWindow.contentView?.wantsLayer = true
    searchWindow.contentView?.layer?.cornerRadius = 18
    searchWindow.contentView?.layer?.cornerCurve = .continuous
    searchWindow.contentView?.layer?.masksToBounds = true

    positionAtCenterOfActiveScreen(searchWindow)

    searchWindowDidResignKeyObserver = NotificationCenter.default.addObserver(
      forName: NSWindow.didResignKeyNotification,
      object: searchWindow,
      queue: .main
    ) { [weak searchWindow] _ in
      searchWindow?.orderOut(nil)
    }

    searchWindowDidBecomeKeyObserver = NotificationCenter.default.addObserver(
      forName: NSWindow.didBecomeKeyNotification,
      object: searchWindow,
      queue: .main
    ) { [weak searchWindow] _ in
      DispatchQueue.main.async {
        guard searchWindow?.isKeyWindow == true else { return }
        NotificationCenter.default.post(name: .focusSearchField, object: nil)
      }
    }
  }

  func showSearchWindow() {
    guard let window = resolvedSearchWindow else { return }
    searchWindowFocusTask?.cancel()
    dismissActionsMenu()
    NSApp.activate(ignoringOtherApps: true)
    window.level = .floating
    window.makeKeyAndOrderFront(nil)
    focusPrimaryControl(in: window)

    // Activation can finish after this method returns, particularly when invoked from the
    // menu-bar extra or the global hot key. In that case the first make-key request is lost while
    // Jolt still appears to be the foreground app. Briefly stabilize key-window and responder
    // state after the invoking menu/event has unwound.
    searchWindowFocusTask = Task { [weak self, weak window] in
      for delay in [50, 100, 200] {
        try? await Task.sleep(for: .milliseconds(delay))
        guard !Task.isCancelled, let self, let window else { return }
        guard self.searchWindow === window, window.isVisible, NSApp.isActive else { return }
        window.makeKeyAndOrderFront(nil)
        self.focusPrimaryControl(in: window)
      }
    }
  }

  func centerSearchWindow() {
    guard let window = resolvedSearchWindow else { return }
    restoreDefaultSizeAndCenter(window)
    showSearchWindow()
  }

  func hideSearchWindow() {
    searchWindowFocusTask?.cancel()
    searchWindow?.orderOut(nil)
  }

  func prepareToOpenSettings() {
    searchWindowFocusTask?.cancel()
    searchWindow?.level = .normal
    NSApp.activate(ignoringOtherApps: true)
  }

  func settingsDidClose() {
    searchWindow?.level = .floating
  }

  private var resolvedSearchWindow: NSWindow? {
    searchWindow
      ?? NSApp.windows.first(where: { $0.identifier?.rawValue == "search" })
  }

  private func enforceSearchWindowSize(_ window: NSWindow) {
    // SwiftUI applies its hidden-title-bar sizing after the representable resolves. Correct the
    // outer frame on the following run-loop pass while preserving the window's current center.
    DispatchQueue.main.async { [weak window] in
      guard let window else { return }
      // SwiftUI finishes resolving scene sizing after the accessor first sees the window. Apply
      // the native constraint again here so both SwiftUI and AppKit agree on the minimum.
      window.minSize = SearchWindowMetrics.minimumSize
      let targetSize = SearchWindowMetrics.defaultSize
      guard window.frame.size != targetSize else { return }
      let center = NSPoint(x: window.frame.midX, y: window.frame.midY)
      window.setFrame(
        NSRect(
          x: center.x - targetSize.width / 2,
          y: center.y - targetSize.height / 2,
          width: targetSize.width,
          height: targetSize.height
        ),
        display: false
      )
    }
  }

  private func positionAtCenterOfActiveScreen(_ window: NSWindow) {
    guard let frame = activeScreen(for: window)?.visibleFrame else { return }
    window.setFrameOrigin(
      NSPoint(
        x: frame.midX - window.frame.width / 2,
        y: frame.midY - window.frame.height / 2
      ))
  }

  private func restoreDefaultSizeAndCenter(_ window: NSWindow) {
    guard let frame = activeScreen(for: window)?.visibleFrame else { return }
    let size = SearchWindowMetrics.defaultSize
    window.setFrame(
      NSRect(
        x: frame.midX - size.width / 2,
        y: frame.midY - size.height / 2,
        width: size.width,
        height: size.height
      ),
      display: true,
      animate: true
    )
  }

  private func activeScreen(for window: NSWindow) -> NSScreen? {
    let mouseLocation = NSEvent.mouseLocation
    return
      NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) ?? window.screen
      ?? NSScreen.main
  }

  private func focusPrimaryControl(in window: NSWindow) {
    // Wait until AppKit has finished making the restored window key before SwiftUI/AppKit fields
    // attempt to become first responder.
    DispatchQueue.main.async { [weak window] in
      guard window?.isKeyWindow == true else { return }
      NotificationCenter.default.post(name: .focusSearchField, object: nil)
    }
  }

  private func restoreSearchFieldFocus() {
    DispatchQueue.main.async { [weak searchWindow] in
      guard searchWindow?.isKeyWindow == true else { return }
      NotificationCenter.default.post(name: .focusSearchField, object: nil)
    }
  }

  private func reconcileSelectedIssue() {
    if isSeeMoreResultsSelected {
      isSeeMoreResultsSelected = false
      selectedIssueID = issues.first?.id
      isIssuePreviewPresented = false
      return
    }
    if selectedIssueID == nil || !issues.contains(where: { $0.id == selectedIssueID }) {
      selectedIssueID = issues.first?.id
      isIssuePreviewPresented = false
    }
  }

  private func applyScopeQuery(_ updated: String) {
    updateAutocomplete(nil)
    inputDidChange(updated)
    restoreSearchFieldFocus()
  }

  private func uniqueValues<Value: Identifiable>(_ values: [Value]) -> [Value]
  where Value.ID: Hashable {
    var seen = Set<Value.ID>()
    return values.filter { seen.insert($0.id).inserted }
  }

  private func uniqueIssueTypesByName(_ values: [JiraIssueType]) -> [JiraIssueType] {
    var seen = Set<String>()
    return values.filter {
      seen.insert($0.name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current))
        .inserted
    }
  }
}

extension Notification.Name {
  static let focusSearchField = Notification.Name("Jolt.focusSearchField")
}
