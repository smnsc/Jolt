import Foundation
import JoltCore

actor JiraMetadataStore {
  private let client: JiraServing
  private let cache: CacheManager
  private var projects: [JiraProject] = []
  private var issueTypes: [JiraIssueType] = []
  private var userSuggestions: [String: [ResolvedShortcut]] = [:]
  private var currentSiteID: String?

  init(client: JiraServing, cache: CacheManager = .shared) {
    self.client = client
    self.cache = cache
  }

  func load(siteID: String, force: Bool = false) async throws {
    if currentSiteID != siteID {
      projects = []
      issueTypes = []
      userSuggestions = [:]
      currentSiteID = siteID
    }
    let cachedSnapshot = !force ? await cache.metadata() : nil
    let matchingSnapshot = cachedSnapshot?.siteID == siteID ? cachedSnapshot : nil
    if let snapshot = matchingSnapshot {
      projects = snapshot.projects
      issueTypes = snapshot.issueTypes
      if snapshot.isFresh { return }
    }
    do {
      async let fetchedProjects = client.projects()
      async let fetchedIssueTypes = client.issueTypes()
      let (projects, issueTypes) = try await (fetchedProjects, fetchedIssueTypes)
      let snapshot = MetadataSnapshot(
        siteID: siteID,
        projects: projects,
        issueTypes: issueTypes,
        fetchedAt: Date()
      )
      self.projects = snapshot.projects
      self.issueTypes = snapshot.issueTypes
      try await cache.save(metadata: snapshot)
    } catch {
      // Stale metadata is still safe for known shortcuts. Keep it available if Jira cannot refresh
      // it so a temporary metadata failure does not block otherwise valid searches.
      if matchingSnapshot != nil { return }
      throw error
    }
  }

  func suggestions(kind: SearchShortcutKind, query: String) async throws -> [ResolvedShortcut] {
    let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
    switch kind {
    case .project:
      return
        ProjectAutocomplete.matches(in: projects, query: needle)
        .prefix(12)
        .map {
          .init(kind: .project, displayName: $0.key, canonicalValue: $0.id, detail: $0.name)
        }
    case .issueType:
      return
        uniqueIssueTypesByName(issueTypes)
        .filter { needle.isEmpty || $0.name.localizedCaseInsensitiveContains(needle) }
        .prefix(12)
        .map { .init(kind: .issueType, displayName: $0.name, canonicalValue: $0.id) }
    case .assignee, .reporter:
      if needle.caseInsensitiveCompare("me") == .orderedSame {
        return [
          .init(kind: kind, displayName: "Me", canonicalValue: "currentUser()")
        ]
      }
      let cacheKey = kind.rawValue + ":" + needle.lowercased()
      if let cached = userSuggestions[cacheKey] { return cached }
      let siteID = currentSiteID
      let remote = try await client.suggestions(field: kind.rawValue, value: needle)
      let suggestions = remote.prefix(12).map {
        ResolvedShortcut(kind: kind, displayName: $0.displayName, canonicalValue: $0.value)
      }
      try Task.checkCancellation()
      guard currentSiteID == siteID else { throw CancellationError() }
      userSuggestions[cacheKey] = suggestions
      return suggestions
    }
  }

  func exactShortcuts(kind: SearchShortcutKind, value: String) async throws -> [ResolvedShortcut] {
    let exact: [ResolvedShortcut]
    switch kind {
    case .project:
      exact = projects.filter {
        $0.key.caseInsensitiveCompare(value) == .orderedSame
          || $0.name.caseInsensitiveCompare(value) == .orderedSame
          || $0.id.caseInsensitiveCompare(value) == .orderedSame
      }.map {
        .init(kind: .project, displayName: $0.key, canonicalValue: $0.id)
      }
    case .issueType:
      let idMatches = issueTypes.filter {
        $0.id.caseInsensitiveCompare(value) == .orderedSame
      }
      let matches = idMatches.isEmpty
        ? issueTypes.filter { $0.name.caseInsensitiveCompare(value) == .orderedSame }
        : idMatches
      exact = uniqueValues(matches).map {
        .init(kind: .issueType, displayName: $0.name, canonicalValue: $0.id)
      }
    case .assignee, .reporter:
      exact = try await suggestions(kind: kind, query: value).filter {
        $0.displayName.caseInsensitiveCompare(value) == .orderedSame
          || $0.canonicalValue.caseInsensitiveCompare(value) == .orderedSame
      }
    }
    let unique = uniqueResolvedShortcuts(exact)
    switch kind {
    case .issueType:
      // Jira can define several project-scoped Issue Types with the same display name. A typed
      // name intentionally resolves to every matching canonical ID so #Epic works across them.
      return unique
    case .project, .assignee, .reporter:
      return unique.count == 1 ? unique : []
    }
  }

  func clearMemory() {
    projects = []
    issueTypes = []
    userSuggestions = [:]
    currentSiteID = nil
  }

  private func uniqueIssueTypesByName(_ values: [JiraIssueType]) -> [JiraIssueType] {
    var seen = Set<String>()
    return values.filter {
      seen.insert($0.name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current))
        .inserted
    }
  }

  private func uniqueValues<Value: Identifiable>(_ values: [Value]) -> [Value]
  where Value.ID: Hashable {
    var seen = Set<Value.ID>()
    return values.filter { seen.insert($0.id).inserted }
  }

  private func uniqueResolvedShortcuts(_ values: [ResolvedShortcut]) -> [ResolvedShortcut] {
    var seen = Set<String>()
    return values.filter { seen.insert($0.canonicalValue).inserted }
  }
}
