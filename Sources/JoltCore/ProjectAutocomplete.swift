import Foundation

public enum ProjectAutocomplete {
  public static func matches(in projects: [JiraProject], query: String) -> [JiraProject] {
    let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !needle.isEmpty else { return projects }

    func rank(_ project: JiraProject) -> Int {
      if project.key.caseInsensitiveCompare(needle) == .orderedSame { return 0 }
      if project.key.range(of: needle, options: [.caseInsensitive, .anchored]) != nil { return 1 }
      if project.key.localizedCaseInsensitiveContains(needle) { return 2 }
      if project.name.localizedCaseInsensitiveContains(needle) { return 3 }
      return 4
    }

    var groups = Array(repeating: [JiraProject](), count: 4)
    for project in projects {
      let priority = rank(project)
      if priority < groups.count { groups[priority].append(project) }
    }
    return groups.flatMap { $0 }
  }
}
