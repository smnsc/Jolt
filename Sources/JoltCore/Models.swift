import Foundation

public enum SearchShortcutKind: String, Codable, CaseIterable, Sendable {
  case project
  case issueType
  case assignee
  case reporter

  public var prefix: Character {
    switch self {
    case .project: return "@"
    case .issueType: return "#"
    case .assignee: return "~"
    case .reporter: return ">"
    }
  }

  public init?(prefix: Character) {
    switch prefix {
    case "@": self = .project
    case "#": self = .issueType
    case "~": self = .assignee
    case ">": self = .reporter
    default: return nil
    }
  }
}

public struct ResolvedShortcut: Codable, Hashable, Identifiable, Sendable {
  public let id: UUID
  public let kind: SearchShortcutKind
  public let displayName: String
  public let canonicalValue: String
  public let detail: String?

  public init(
    id: UUID = UUID(),
    kind: SearchShortcutKind,
    displayName: String,
    canonicalValue: String,
    detail: String? = nil
  ) {
    self.id = id
    self.kind = kind
    self.displayName = displayName
    self.canonicalValue = canonicalValue
    self.detail = detail
  }

  public var insertionText: String {
    Self.insertionText(kind: kind, displayName: displayName)
  }

  public func insertionText(preserving query: String) -> String {
    guard !query.isEmpty else { return insertionText }
    if let range = displayName.range(of: query, options: [.caseInsensitive, .anchored]) {
      return Self.insertionText(
        kind: kind, displayName: query + String(displayName[range.upperBound...]))
    }
    // Exact project-name aliases and canonical values also resolve without changing the input.
    if canonicalValue.caseInsensitiveCompare(query) == .orderedSame
      || (kind == .project && detail?.caseInsensitiveCompare(query) == .orderedSame)
    {
      return Self.insertionText(kind: kind, displayName: query)
    }
    return insertionText
  }

  private static func insertionText(kind: SearchShortcutKind, displayName: String) -> String {
    let escaped = displayName.replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "\"", with: "\\\"")
    if escaped.contains(where: { $0.isWhitespace }) {
      return "\(kind.prefix)\"\(escaped)\""
    }
    return "\(kind.prefix)\(escaped)"
  }
}

public struct UnresolvedShortcut: Codable, Hashable, Sendable {
  public let kind: SearchShortcutKind
  public let value: String
  public let sourceText: String

  public init(kind: SearchShortcutKind, value: String, sourceText: String) {
    self.kind = kind
    self.value = value
    self.sourceText = sourceText
  }
}

public struct ParsedSearch: Equatable, Sendable {
  public var plainTerms: [String]
  public var projects: [ResolvedShortcut]
  public var issueTypes: [ResolvedShortcut]
  public var reporters: [ResolvedShortcut]
  public var assignees: [ResolvedShortcut]
  public var unresolvedShortcuts: [UnresolvedShortcut]
  public var directIssueKey: String?

  public init(
    plainTerms: [String] = [],
    projects: [ResolvedShortcut] = [],
    issueTypes: [ResolvedShortcut] = [],
    assignees: [ResolvedShortcut] = [],
    reporters: [ResolvedShortcut] = [],
    unresolvedShortcuts: [UnresolvedShortcut] = [],
    directIssueKey: String? = nil
  ) {
    self.plainTerms = plainTerms
    self.projects = projects
    self.issueTypes = issueTypes
    self.assignees = assignees
    self.reporters = reporters
    self.unresolvedShortcuts = unresolvedShortcuts
    self.directIssueKey = directIssueKey
  }
}

public struct JiraSite: Codable, Hashable, Identifiable, Sendable {
  public let id: String
  public let url: URL
  public let name: String
  public let scopes: [String]
  public let avatarURL: URL?

  public init(id: String, url: URL, name: String, scopes: [String] = [], avatarURL: URL? = nil) {
    self.id = id
    self.url = url
    self.name = name
    self.scopes = scopes
    self.avatarURL = avatarURL
  }

  private enum CodingKeys: String, CodingKey {
    case id, url, name, scopes
    case avatarURL = "avatarUrl"
  }
}

public struct JiraProject: Codable, Hashable, Identifiable, Sendable {
  public let id: String
  public let key: String
  public let name: String

  public init(id: String, key: String, name: String) {
    self.id = id
    self.key = key
    self.name = name
  }
}

public struct JiraIssueType: Codable, Hashable, Identifiable, Sendable {
  public let id: String
  public let name: String
  public let iconURL: URL?

  public init(id: String, name: String, iconURL: URL? = nil) {
    self.id = id
    self.name = name
    self.iconURL = iconURL
  }

  private enum CodingKeys: String, CodingKey {
    case id, name
    case iconURL = "iconUrl"
  }
}

public struct JiraUser: Codable, Hashable, Identifiable, Sendable {
  public let accountId: String
  public let displayName: String
  public let avatarURL: URL?

  public var id: String { accountId }

  public init(accountId: String, displayName: String, avatarURL: URL? = nil) {
    self.accountId = accountId
    self.displayName = displayName
    self.avatarURL = avatarURL
  }
}

public enum JiraStatusCategory: String, Codable, Sendable {
  case new
  case indeterminate
  case done
  case unknown

  public init(from decoder: Decoder) throws {
    let value = try decoder.singleValueContainer().decode(String.self)
    self = JiraStatusCategory(rawValue: value) ?? .unknown
  }
}

public struct JiraStatus: Codable, Hashable, Sendable {
  public let name: String
  public let category: JiraStatusCategory

  public init(name: String, category: JiraStatusCategory) {
    self.name = name
    self.category = category
  }
}

public struct JiraIssue: Codable, Hashable, Identifiable, Sendable {
  public let id: String
  public let key: String
  public let summary: String
  public let description: String?
  public let project: JiraProject
  public let issueType: JiraIssueType
  public let status: JiraStatus

  public init(
    id: String,
    key: String,
    summary: String,
    description: String? = nil,
    project: JiraProject,
    issueType: JiraIssueType,
    status: JiraStatus
  ) {
    self.id = id
    self.key = key
    self.summary = summary
    self.description = description
    self.project = project
    self.issueType = issueType
    self.status = status
  }
}

public struct JiraAutocompleteSuggestion: Codable, Hashable, Identifiable, Sendable {
  public let displayName: String
  public let value: String

  public var id: String { "\(displayName)\u{0}\(value)" }

  public init(displayName: String, value: String) {
    self.displayName = displayName
    self.value = value
  }
}
