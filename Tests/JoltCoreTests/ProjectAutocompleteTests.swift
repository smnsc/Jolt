import Testing
@testable import JoltCore

struct ProjectAutocompleteTests {
  private let projects = [
    JiraProject(id: "1", key: "CAB", name: "Change Management (Release)"),
    JiraProject(id: "2", key: "XRE", name: "Other"),
    JiraProject(id: "3", key: "RED", name: "Red team"),
    JiraProject(id: "4", key: "RE", name: "Rhino Entertainment"),
    JiraProject(id: "5", key: "OPS", name: "Operations"),
  ]

  @Test func exactKeyLeadsNameMatches() {
    #expect(ProjectAutocomplete.matches(in: projects, query: "re").map(\.key)
      == ["RE", "RED", "XRE", "CAB"])
  }

  @Test func typingRefinesAndClearingRestoresSuggestions() {
    #expect(ProjectAutocomplete.matches(in: projects, query: "red").map(\.key) == ["RED"])
    #expect(ProjectAutocomplete.matches(in: projects, query: "missing").isEmpty)
    #expect(ProjectAutocomplete.matches(in: projects, query: "") == projects)
    #expect(ProjectAutocomplete.matches(in: projects, query: " RELEASE ").map(\.key) == ["CAB"])
  }
}
