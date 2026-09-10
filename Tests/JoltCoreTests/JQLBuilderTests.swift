import Testing

@testable import JoltCore

@Suite struct JQLBuilderTests {
  @Test func reportersCombineWithOtherCategoriesAndDeduplicate() throws {
    let jane = ResolvedShortcut(kind: .reporter, displayName: "Jane", canonicalValue: "account-1")
    let parsed = ParsedSearch(
      plainTerms: ["export"],
      projects: [.init(kind: .project, displayName: "DEV", canonicalValue: "10")],
      issueTypes: [.init(kind: .issueType, displayName: "Bug", canonicalValue: "20")],
      assignees: [.init(kind: .assignee, displayName: "Me", canonicalValue: "currentUser()")],
      reporters: [jane, .init(kind: .reporter, displayName: "Me", canonicalValue: "currentUser()"), jane]
    )
    #expect(try JQLBuilder().build(parsed: parsed)
      == #"project IN ("10") AND issuetype IN ("20") AND assignee IN (currentUser()) AND reporter IN ("account-1", currentUser()) AND text ~ "export*" ORDER BY lastViewed DESC"#)
  }

  @Test func unresolvedReporterCannotReachJira() {
    let parsed = SearchQueryParser().parse(">unknown")
    #expect(throws: JQLBuilderError.unresolvedShortcuts(parsed.unresolvedShortcuts)) {
      try JQLBuilder().build(parsed: parsed)
    }
  }

  @Test func raycastExampleUsesOrWithinCategoriesAndAndBetweenTerms() throws {
    let parsed = ParsedSearch(
      plainTerms: ["pdf", "export"],
      projects: [
        .init(kind: .project, displayName: "DEV", canonicalValue: "DEV"),
        .init(kind: .project, displayName: "IT", canonicalValue: "IT"),
      ],
      issueTypes: [
        .init(kind: .issueType, displayName: "Bug", canonicalValue: "10001"),
        .init(kind: .issueType, displayName: "Story", canonicalValue: "10002"),
      ]
    )

    let jql = try JQLBuilder().build(parsed: parsed)
    #expect(
      jql
        == #"project IN ("DEV", "IT") AND issuetype IN ("10001", "10002") AND text ~ "pdf*" AND text ~ "export*" ORDER BY lastViewed DESC"#
    )
  }

  @Test func emptySearchUsesRecentIssues() throws {
    #expect(
      try JQLBuilder().build(input: "")
        == "updated >= -180d ORDER BY lastViewed DESC")
  }

  @Test func meCanBeMixedWithAccountIDs() throws {
    let parsed = ParsedSearch(assignees: [
      .init(kind: .assignee, displayName: "Me", canonicalValue: "currentUser()"),
      .init(kind: .assignee, displayName: "Jane Smith", canonicalValue: "abc-123"),
    ])
    #expect(
      try JQLBuilder().build(parsed: parsed)
        == #"assignee IN (currentUser(), "abc-123") ORDER BY lastViewed DESC"#)
  }

  @Test func unresolvedShortcutCannotReachJira() {
    do {
      _ = try JQLBuilder().build(input: "#unknown")
      Issue.record("Expected unresolved shortcut rejection")
    } catch JQLBuilderError.unresolvedShortcuts(let values) {
      #expect(values.first?.value == "unknown")
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }

  @Test func quotesAndBackslashesAreEscaped() throws {
    let parsed = ParsedSearch(plainTerms: [#"a"b\c"#])
    let jql = try JQLBuilder().build(parsed: parsed)
    #expect(jql == #"text ~ "a\"b\\c*" ORDER BY lastViewed DESC"#)
  }

  @Test func directIssueKey() throws {
    #expect(
      try JQLBuilder().build(input: "dev-42")
        == #"key = "DEV-42" ORDER BY lastViewed DESC"#)
  }
}
