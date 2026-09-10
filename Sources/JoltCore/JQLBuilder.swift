import Foundation

public enum JQLBuilderError: LocalizedError, Equatable {
  case unresolvedShortcuts([UnresolvedShortcut])

  public var errorDescription: String? {
    switch self {
    case .unresolvedShortcuts(let shortcuts):
      let values = shortcuts.map(\.sourceText).joined(separator: ", ")
      return "Choose a Jira match for: \(values)"
    }
  }
}

public struct JQLBuilder: Sendable {
  public init() {}

  public func build(input: String) throws -> String {
    try build(parsed: SearchQueryParser().parse(input))
  }

  public func build(parsed: ParsedSearch) throws -> String {
    guard parsed.unresolvedShortcuts.isEmpty else {
      throw JQLBuilderError.unresolvedShortcuts(parsed.unresolvedShortcuts)
    }

    var conditions: [String] = []
    if let key = parsed.directIssueKey {
      conditions.append("key = \(quoted(key))")
    } else {
      appendInClause(
        field: "project", values: parsed.projects.map(\.canonicalValue), to: &conditions)
      appendInClause(
        field: "issuetype", values: parsed.issueTypes.map(\.canonicalValue), to: &conditions)
      appendInClause(
        field: "assignee",
        values: parsed.assignees.map(\.canonicalValue),
        functionValues: ["currentUser()"],
        to: &conditions
      )
      appendInClause(
        field: "reporter",
        values: parsed.reporters.map(\.canonicalValue),
        functionValues: ["currentUser()"],
        to: &conditions
      )
      conditions.append(contentsOf: parsed.plainTerms.map { "text ~ \(quoted($0 + "*"))" })
    }

    if conditions.isEmpty {
      conditions.append("updated >= -180d")
    }

    return conditions.joined(separator: " AND ") + " ORDER BY lastViewed DESC"
  }

  private func appendInClause(
    field: String,
    values: [String],
    functionValues: Set<String> = [],
    to conditions: inout [String]
  ) {
    let unique = values.reduce(into: [String]()) { values, value in
      if !values.contains(value) { values.append(value) }
    }
    guard !unique.isEmpty else { return }
    let rendered = unique.map { functionValues.contains($0) ? $0 : quoted($0) }
    conditions.append("\(field) IN (\(rendered.joined(separator: ", ")))")
  }

  private func quoted(_ value: String) -> String {
    let escaped = value.replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "\"", with: "\\\"")
    return "\"\(escaped)\""
  }
}
