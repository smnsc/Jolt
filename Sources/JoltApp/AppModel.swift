import AppKit
import Combine
import Foundation
import JoltCore

struct AutocompleteContext: Equatable {
  let kind: SearchShortcutKind
  let query: String
}

enum SearchWindowMetrics {
  static let defaultSize = NSSize(width: 800, height: 500)
  static let minimumSize = NSSize(width: 640, height: 400)
}

private struct SearchCacheKey: Hashable {
  let siteID: String
  let jql: String
  let resultLimit: Int
}

private struct SearchCacheEntry {
  let issues: [JiraIssue]
  let fetchedAt: Date

  var isFresh: Bool { fetchedAt.timeIntervalSinceNow > -60 }
}

private struct IssueDescriptionCacheKey: Hashable {
  let siteID: String
  let issueID: String
}

private enum CachedIssueDescription {
  case value(JiraDescription?)
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
  @Published var shortcutErrorMessage: String?
  @Published var autocompleteContext: AutocompleteContext?
  @Published private(set) var autocompleteSuggestions: [ResolvedShortcut] = []
  @Published var autocompleteSelection = 0
  @Published private(set) var isActionsMenuPresented = false
  @Published private(set) var selectedIssueActionIndex = 0
  @Published private(set) var isIssuePreviewPresented = false
  @Published private(set) var issuePreviewDescription: JiraDescription?
  @Published private(set) var isIssuePreviewLoading = false
  @Published private(set) var issuePreviewErrorMessage: String?
  @Published private(set) var isSeeMoreResultsSelected = false

  let preferences = AppPreferences.shared
  let auth: JiraAuthSession
  let client: JiraClient
  let cache: CacheManager
  let metadata: JiraMetadataStore
  let images: ImageRepository

  private var searchTask: Task<Void, Never>?
  private var previewTask: Task<Void, Never>?
  private var previewPrefetchTask: Task<Void, Never>?
  private var autocompleteTask: Task<Void, Never>?
  private var connectionTask: Task<Void, Never>?
  private weak var searchWindow: NSWindow?
  private var hiddenSearchWindowFrame: NSRect?
  private var searchWindowDidResignKeyObserver: NSObjectProtocol?
  private var searchWindowDidBecomeKeyObserver: NSObjectProtocol?
  private var screenParametersObserver: NSObjectProtocol?
  private var searchWindowFocusTask: Task<Void, Never>?
  private var searchResetTask: Task<Void, Never>?
  private var searchResetDeadline: Date?
  private weak var settingsWindow: NSWindow?
  private var settingsDidBecomeKeyObserver: NSObjectProtocol?
  private var isSettingsPresented = false
  private var activationPolicyTransitionID: UUID?
  private var handlesPendingActivation = false
  private var displayedJQL: String?
  private var searchGeneration = 0
  private var searchCache: [SearchCacheKey: SearchCacheEntry] = [:]
  private var descriptionCache: [IssueDescriptionCacheKey: CachedIssueDescription] = [:]
  private var descriptionTasks: [IssueDescriptionCacheKey: Task<JiraDescription?, Error>] = [:]

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
      cancelIssuePreviewWork()
      descriptionTasks.values.forEach { $0.cancel() }
      descriptionTasks = [:]
      descriptionCache = [:]
      searchCache = [:]
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

    let parsedInput = SearchQueryParser().parse(input)
    let canSearchWithoutMetadata = parsedInput.unresolvedShortcuts.isEmpty
    if canSearchWithoutMetadata {
      scheduleSearch(immediate: true)
    }
    do {
      try await metadata.load(siteID: site.id)
      if !canSearchWithoutMetadata {
        scheduleSearch(immediate: true)
      }
    } catch {
      errorMessage = error.userFacingMessage
    }
  }

  func logout() {
    connectionTask?.cancel()
    searchTask?.cancel()
    autocompleteTask?.cancel()
    cancelIssuePreviewWork()
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
      searchCache = [:]
      descriptionCache = [:]
      descriptionTasks.values.forEach { $0.cancel() }
      descriptionTasks = [:]
      isIssuePreviewPresented = false
      input = ""
    }
  }

  func clearCachedData() async {
    searchTask?.cancel()
    cancelIssuePreviewWork()
    isSearching = false
    issues = []
    selectedIssueID = nil
    isSeeMoreResultsSelected = false
    displayedJQL = nil
    isIssuePreviewPresented = false
    images.clearMemory()
    searchCache = [:]
    descriptionCache = [:]
    descriptionTasks.values.forEach { $0.cancel() }
    descriptionTasks = [:]
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
    updateInput(input, immediate: false)
  }

  func inputDidCompleteShortcut(_ input: String) {
    updateInput(input, immediate: true)
  }

  private func updateInput(_ input: String, immediate: Bool) {
    dismissActionsMenu()
    dismissIssuePreview()
    previewPrefetchTask?.cancel()
    previewPrefetchTask = nil
    if isSeeMoreResultsSelected {
      isSeeMoreResultsSelected = false
      selectedIssueID = issues.first?.id
    }
    self.input = input
    scheduleSearch(immediate: immediate)
  }

  func handleSearchEscape() {
    guard input.isEmpty else {
      updateAutocomplete(nil)
      updateInput("", immediate: true)
      restoreSearchFieldFocus()
      return
    }

    hideSearchWindow()
  }

  func scheduleSearch(immediate: Bool = false) {
    searchTask?.cancel()
    guard isAuthenticated, let scheduledSiteID = selectedSite?.id else { return }
    searchGeneration += 1
    let generation = searchGeneration
    let scheduledInput = input
    let scheduledResultLimit = preferences.searchResultLimit.rawValue
    isSearching = true
    searchTask = Task {
      defer {
        if searchGeneration == generation { isSearching = false }
      }
      if !immediate {
        try? await Task.sleep(for: .milliseconds(170))
      }
      guard !Task.isCancelled else { return }
      do {
        let resolvedInput = await resolvingShortcuts(in: scheduledInput)
        guard !Task.isCancelled, input == scheduledInput,
          selectedSite?.id == scheduledSiteID
        else { return }
        let jql = try JQLBuilder().build(parsed: resolvedInput)
        errorMessage = nil
        let cacheKey = SearchCacheKey(
          siteID: scheduledSiteID,
          jql: jql,
          resultLimit: scheduledResultLimit
        )
        if let cached = searchCache[cacheKey], cached.isFresh {
          publishSearchResult(cached.issues, jql: jql)
        }
        let result = try await client.search(jql: jql, maxResults: scheduledResultLimit)
        guard !Task.isCancelled, input == scheduledInput,
          selectedSite?.id == scheduledSiteID
        else { return }
        searchCache[cacheKey] = SearchCacheEntry(issues: result, fetchedAt: Date())
        trimSearchCache()
        publishSearchResult(result, jql: jql)
      } catch is CancellationError {
        return
      } catch {
        guard !Task.isCancelled else { return }
        errorMessage = error.userFacingMessage
      }
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
      if context.kind == .assignee || context.kind == .reporter { try? await Task.sleep(for: .milliseconds(180)) }
      guard !Task.isCancelled else { return }
      do {
        let suggestions = try await metadata.suggestions(kind: context.kind, query: context.query)
        guard !Task.isCancelled, autocompleteContext == context else { return }
        autocompleteSuggestions = suggestions
      } catch {
        guard !Task.isCancelled, autocompleteContext == context else { return }
        autocompleteSuggestions = []
      }
    }
  }

  private func resolvingShortcuts(in text: String) async -> ParsedSearch {
    var parsed = SearchQueryParser().parse(text)
    let shortcuts = parsed.unresolvedShortcuts
    parsed.unresolvedShortcuts = []

    let resolvedShortcuts = await withTaskGroup(
      of: (Int, UnresolvedShortcut, [ResolvedShortcut]?).self,
      returning: [(Int, UnresolvedShortcut, [ResolvedShortcut]?)].self
    ) { group in
      for (index, shortcut) in shortcuts.enumerated() {
        group.addTask { [metadata] in
          let resolved = try? await metadata.exactShortcuts(
            kind: shortcut.kind,
            value: shortcut.value
          )
          return (index, shortcut, resolved)
        }
      }
      var values: [(Int, UnresolvedShortcut, [ResolvedShortcut]?)] = []
      for await value in group { values.append(value) }
      return values.sorted { $0.0 < $1.0 }
    }

    for (_, shortcut, resolved) in resolvedShortcuts {
      guard let resolved, !resolved.isEmpty else {
        parsed.unresolvedShortcuts.append(shortcut)
        continue
      }

      switch shortcut.kind {
      case .project: parsed.projects.append(contentsOf: resolved)
      case .issueType: parsed.issueTypes.append(contentsOf: resolved)
      case .assignee: parsed.assignees.append(contentsOf: resolved)
      case .reporter: parsed.reporters.append(contentsOf: resolved)
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
    scheduleDescriptionPrefetch(for: selectedIssue)
  }

  func selectIssue(_ id: String) {
    dismissActionsMenu()
    selectedIssueID = id
    isSeeMoreResultsSelected = false
    scheduleDescriptionPrefetch(for: selectedIssue)
    restoreSearchFieldFocus()
  }

  func presentIssuePreview() {
    guard let issue = selectedIssue, let siteID = selectedSite?.id else { return }
    updateAutocomplete(nil)
    dismissActionsMenu()
    isIssuePreviewPresented = true
    issuePreviewErrorMessage = nil
    previewTask?.cancel()

    let cacheKey = IssueDescriptionCacheKey(siteID: siteID, issueID: issue.id)
    if case .value(let description) = descriptionCache[cacheKey] {
      issuePreviewDescription = description
      isIssuePreviewLoading = false
      return
    }

    issuePreviewDescription = nil
    isIssuePreviewLoading = true
    previewTask = Task {
      do {
        let description = try await description(for: issue, siteID: siteID)
        guard !Task.isCancelled, isIssuePreviewPresented,
          selectedIssueID == issue.id, selectedSite?.id == siteID
        else { return }
        issuePreviewDescription = description
        isIssuePreviewLoading = false
      } catch is CancellationError {
        return
      } catch {
        guard !Task.isCancelled, isIssuePreviewPresented,
          selectedIssueID == issue.id, selectedSite?.id == siteID
        else { return }
        issuePreviewErrorMessage = error.userFacingMessage
        isIssuePreviewLoading = false
      }
    }
  }

  func dismissIssuePreview() {
    guard isIssuePreviewPresented else { return }
    dismissActionsMenu()
    isIssuePreviewPresented = false
    previewTask?.cancel()
    previewTask = nil
    issuePreviewDescription = nil
    isIssuePreviewLoading = false
    issuePreviewErrorMessage = nil
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

    // Start each run at the default frame rather than restoring old session geometry.
    searchWindow.isRestorable = false
    searchWindow.styleMask.insert([.fullSizeContentView, .resizable])
    // Hiding the title-bar button alone still allows minimization through Command-M.
    searchWindow.styleMask.remove(.miniaturizable)
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
    if let screenParametersObserver {
      NotificationCenter.default.removeObserver(screenParametersObserver)
    }

    searchWindow.level = .floating
    searchWindow.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    searchWindow.isReleasedWhenClosed = false
    // SwiftUI's hidden-title-bar window remains titled underneath its custom chrome. Do not
    // remove that style: borderless windows cannot reliably become key again after orderOut.
    // Make the content view occupy the title-bar region as well, so the custom search surface
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

    screenParametersObserver = NotificationCenter.default.addObserver(
      forName: NSApplication.didChangeScreenParametersNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated {
        // Pending activation retries hold coordinates from the previous display geometry.
        self?.searchWindowFocusTask?.cancel()
      }
      // Let AppKit finish updating screen membership and constraining the window first.
      DispatchQueue.main.async { [weak self] in
        guard let self, let window = self.searchWindow,
          let screen = window.screen ?? NSScreen.main ?? NSScreen.screens.first
        else { return }
        self.searchWindowFocusTask?.cancel()
        self.positionAtCenter(window, in: screen.visibleFrame)
        if self.hiddenSearchWindowFrame != nil || !window.isVisible {
          self.hiddenSearchWindowFrame = window.frame
        }
      }
    }

    searchWindowDidResignKeyObserver = NotificationCenter.default.addObserver(
      forName: NSWindow.didResignKeyNotification,
      object: searchWindow,
      queue: .main
    ) { [weak self] _ in
      // Let Settings finish appearing before deciding whether this focus change dismisses search.
      DispatchQueue.main.async { [weak self] in
        guard let self, self.searchWindow?.isKeyWindow != true else { return }
        guard self.activationPolicyTransitionID == nil else { return }
        guard !self.isSettingsPresented || !NSApp.isActive else { return }
        self.hideSearchWindow()
      }
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
    finishPendingSearchReset()
    searchWindowFocusTask?.cancel()
    dismissActionsMenu()
    // Capture geometry before activation: ordering a SwiftUI window forward can reapply
    // scene restoration. Keep the user’s frame throughout the activation retry period.
    let frameToRestore = hiddenSearchWindowFrame ?? window.frame
    hiddenSearchWindowFrame = nil
    activateForExplicitWindowAction()
    window.level = isSettingsPresented ? .normal : .floating
    window.makeKeyAndOrderFront(nil)
    restoreSearchWindowFrame(frameToRestore, in: window)
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
        guard !window.inLiveResize else { return }
        // Re-order only when activation actually lost the key-window request.
        if !window.isKeyWindow { window.makeKeyAndOrderFront(nil) }
        self.restoreSearchWindowFrame(frameToRestore, in: window)
        self.focusPrimaryControl(in: window)
      }
    }
  }

  func toggleSearchWindow() {
    guard let window = resolvedSearchWindow else { return }
    if window.isVisible {
      hideSearchWindow()
    } else {
      showSearchWindow()
    }
  }

  func centerSearchWindow() {
    guard let window = resolvedSearchWindow else { return }
    hiddenSearchWindowFrame = nil
    restoreDefaultSizeAndCenter(window)
    showSearchWindow()
  }

  func hideSearchWindow() {
    searchWindowFocusTask?.cancel()
    guard let window = searchWindow, window.isVisible else { return }
    hiddenSearchWindowFrame = window.frame
    window.orderOut(nil)
    scheduleSearchReset()
  }

  private func scheduleSearchReset() {
    searchResetTask?.cancel()
    searchResetTask = nil
    searchResetDeadline = nil
    let delay = preferences.searchResetDelay
    // An issue opened from the default results still needs to return to search on reset.
    guard delay != .never, !input.isEmpty || isIssuePreviewPresented else { return }
    guard delay != .immediately else {
      resetSearchQuery()
      return
    }
    searchResetDeadline = Date().addingTimeInterval(TimeInterval(delay.rawValue))
    searchResetTask = Task { [weak self] in
      try? await Task.sleep(for: .seconds(delay.rawValue))
      guard !Task.isCancelled, let self else { return }
      guard self.searchWindow?.isVisible != true else { return }
      self.searchResetDeadline = nil
      self.searchResetTask = nil
      self.resetSearchQuery()
    }
  }

  private func finishPendingSearchReset() {
    // Check the deadline as well as the task so returning after sleep still resets the query.
    if let deadline = searchResetDeadline, deadline <= Date() {
      resetSearchQuery()
    }
    searchResetTask?.cancel()
    searchResetTask = nil
    searchResetDeadline = nil
  }

  private func resetSearchQuery() {
    updateAutocomplete(nil)
    updateInput("", immediate: true)
  }

  private func restoreSearchWindowFrame(_ frame: NSRect, in window: NSWindow) {
    guard !window.inLiveResize, window.frame != frame else { return }
    window.setFrame(frame, display: true)
  }

  func register(settingsWindow: NSWindow) {
    guard self.settingsWindow !== settingsWindow else { return }
    self.settingsWindow = settingsWindow
    if let settingsDidBecomeKeyObserver {
      NotificationCenter.default.removeObserver(settingsDidBecomeKeyObserver)
    }
    settingsDidBecomeKeyObserver = NotificationCenter.default.addObserver(
      forName: NSWindow.didBecomeKeyNotification,
      object: settingsWindow,
      queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated {
        // A hot-key or Cmd+Tab search activation may still have focus retries pending.
        self?.searchWindowFocusTask?.cancel()
      }
    }
    if isSettingsPresented, settingsWindow.isVisible {
      searchWindow?.order(.below, relativeTo: settingsWindow.windowNumber)
    }
  }

  func prepareToOpenSettings() {
    isSettingsPresented = true
    searchWindowFocusTask?.cancel()
    activateForExplicitWindowAction()
    guard let window = resolvedSearchWindow else { return }
    finishPendingSearchReset()
    window.level = .normal
    let frame = hiddenSearchWindowFrame ?? window.frame
    hiddenSearchWindowFrame = nil
    // Show the live preview without taking keyboard focus away from Settings.
    if let settingsWindow, settingsWindow.isVisible {
      window.order(.below, relativeTo: settingsWindow.windowNumber)
    } else {
      window.orderFront(nil)
    }
    restoreSearchWindowFrame(frame, in: window)
  }

  private func activateForExplicitWindowAction() {
    // The caller owns presentation for this activation, including Settings and search focus.
    if !NSApp.isActive { handlesPendingActivation = true }
    NSApp.activate(ignoringOtherApps: true)
  }

  func applyActivationPolicy(_ policy: NSApplication.ActivationPolicy) {
    // Changing between regular and accessory can hide windows and temporarily resign
    // activation. Preserve presentation only when the user is currently in Jolt.
    guard NSApp.isActive else {
      NSApp.setActivationPolicy(policy)
      return
    }
    let windows = NSApp.orderedWindows.filter { $0.isVisible && !$0.isMiniaturized }
    let frames = windows.map(\.frame)
    let keyWindow = NSApp.keyWindow
    let transitionID = UUID()
    activationPolicyTransitionID = transitionID
    searchWindowFocusTask?.cancel()
    NSApp.setActivationPolicy(policy)

    // Let the policy change finish before restoring the original stacking and focus.
    DispatchQueue.main.async { [weak self] in
      guard let self, self.activationPolicyTransitionID == transitionID else { return }
      NSApp.activate(ignoringOtherApps: true)
      for (window, frame) in zip(windows, frames).reversed() {
        window.orderFront(nil)
        window.setFrame(frame, display: true)
      }
      keyWindow?.makeKeyAndOrderFront(nil)
      DispatchQueue.main.async { [weak self] in
        guard let self, self.activationPolicyTransitionID == transitionID else { return }
        self.activationPolicyTransitionID = nil
      }
    }
  }

  func applicationDidBecomeActive() {
    guard activationPolicyTransitionID == nil else { return }
    let wasHandled = handlesPendingActivation
    handlesPendingActivation = false
    guard !wasHandled else { return }
    showSearchWindow()
  }

  func applicationDidResignActive() {
    guard activationPolicyTransitionID == nil else { return }
    // Do not let an interrupted explicit activation suppress a later Cmd+Tab return.
    handlesPendingActivation = false
    hideSearchWindow()
  }

  func settingsDidClose() {
    isSettingsPresented = false
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

  // Leave 40% of the spare vertical space above the window for a slightly raised center.
  private func positionAtCenterOfActiveScreen(_ window: NSWindow) {
    guard let frame = activeScreen(for: window)?.visibleFrame else { return }
    positionAtCenter(window, in: frame)
  }

  private func positionAtCenter(_ window: NSWindow, in frame: NSRect) {
    window.setFrameOrigin(
      NSPoint(
        x: frame.midX - window.frame.width / 2,
        y: frame.minY + max(0, frame.height - window.frame.height) * 0.6
      ))
  }

  private func restoreDefaultSizeAndCenter(_ window: NSWindow) {
    guard let frame = activeScreen(for: window)?.visibleFrame else { return }
    let size = SearchWindowMetrics.defaultSize
    window.setFrame(
      NSRect(
        x: frame.midX - size.width / 2,
        y: frame.minY + max(0, frame.height - size.height) * 0.6,
        width: size.width,
        height: size.height
      ),
      display: true,
      animate: false
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
    updateInput(updated, immediate: true)
    restoreSearchFieldFocus()
  }

  private func publishSearchResult(_ result: [JiraIssue], jql: String) {
    issues = result
    displayedJQL = jql
    reconcileSelectedIssue()
    scheduleDescriptionPrefetch(for: selectedIssue)
  }

  private func trimSearchCache() {
    while searchCache.count > 20,
      let oldestKey = searchCache.min(by: { $0.value.fetchedAt < $1.value.fetchedAt })?.key
    {
      searchCache.removeValue(forKey: oldestKey)
    }
  }

  private func scheduleDescriptionPrefetch(for issue: JiraIssue?) {
    previewPrefetchTask?.cancel()
    guard let issue, let siteID = selectedSite?.id else { return }
    let cacheKey = IssueDescriptionCacheKey(siteID: siteID, issueID: issue.id)
    guard descriptionCache[cacheKey] == nil else { return }

    previewPrefetchTask = Task(priority: .utility) {
      try? await Task.sleep(for: .milliseconds(120))
      guard !Task.isCancelled else { return }
      _ = try? await description(for: issue, siteID: siteID)
    }
  }

  private func description(for issue: JiraIssue, siteID: String) async throws -> JiraDescription? {
    let cacheKey = IssueDescriptionCacheKey(siteID: siteID, issueID: issue.id)
    if case .value(let description) = descriptionCache[cacheKey] { return description }
    if let task = descriptionTasks[cacheKey] { return try await task.value }

    let task = Task { [client] in
      try await client.issueDescription(issueID: issue.id)
    }
    descriptionTasks[cacheKey] = task
    do {
      let value = try await task.value
      descriptionTasks[cacheKey] = nil
      if selectedSite?.id == siteID {
        descriptionCache[cacheKey] = .value(value)
      }
      return value
    } catch {
      descriptionTasks[cacheKey] = nil
      throw error
    }
  }

  private func cancelIssuePreviewWork() {
    previewTask?.cancel()
    previewTask = nil
    previewPrefetchTask?.cancel()
    previewPrefetchTask = nil
    issuePreviewDescription = nil
    isIssuePreviewLoading = false
    issuePreviewErrorMessage = nil
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
