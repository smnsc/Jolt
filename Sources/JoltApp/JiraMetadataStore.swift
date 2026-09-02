import Foundation
import JoltCore

actor JiraMetadataStore {
  private let client: JiraServing
  private let cache: CacheManager
  private var projects: [JiraProject] = []
  private var issueTypes: [JiraIssueType] = []
  private var assigneeSuggestions: [String: [ResolvedShortcut]] = [:]
  private var currentSiteID: String?

  init(client: JiraServing, cache: CacheManager = .shared) {
    self.client = client
    self.cache = cache
  }

  func load(siteID: String, force: Bool = false) async throws {
    if currentSiteID != siteID {
      projects = []
      issueTypes = []
      assigneeSuggestions = [:]
      currentSiteID = siteID
    }
    if !force, let snapshot = await cache.metadata(), snapshot.siteID == siteID,
      snapshot.isFresh
    {
      projects = snapshot.projects
      issueTypes = snapshot.issueTypes
      return
    }
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
  }

  func suggestions(kind: SearchShortcutKind, query: String) async throws -> [ResolvedShortcut] {
    let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
    switch kind {
    case .project:
      return
        projects
        .filter {
          needle.isEmpty || $0.key.localizedCaseInsensitiveContains(needle)
            || $0.name.localizedCaseInsensitiveContains(needle)
        }
        .prefix(12)
        .map {
          .init(kind: .project, displayName: $0.key, canonicalValue: $0.id)
        }
    case .issueType:
      return
        uniqueIssueTypesByName(issueTypes)
        .filter { needle.isEmpty || $0.name.localizedCaseInsensitiveContains(needle) }
        .prefix(12)
        .map { .init(kind: .issueType, displayName: $0.name, canonicalValue: $0.id) }
    case .assignee:
      if needle.caseInsensitiveCompare("me") == .orderedSame {
        return [
          .init(kind: .assignee, displayName: "Me", canonicalValue: "currentUser()")
        ]
      }
      let cacheKey = needle.lowercased()
      if let cached = assigneeSuggestions[cacheKey] { return cached }
      let remote = try await client.suggestions(field: "assignee", value: needle)
      let suggestions = remote.prefix(12).map {
        ResolvedShortcut(kind: .assignee, displayName: $0.displayName, canonicalValue: $0.value)
      }
      assigneeSuggestions[cacheKey] = suggestions
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
    case .assignee:
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
    case .project, .assignee:
      return unique.count == 1 ? unique : []
    }
  }

  func clearMemory() {
    projects = []
    issueTypes = []
    assigneeSuggestions = [:]
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
