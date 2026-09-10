import Foundation
import Testing

@testable import JoltCore

@Suite struct SearchParserTests {
  @Test func reporterShortcutsRequireResolutionAndPreventDirectLookup() {
    let parsed = SearchQueryParser().parse(#"dev-42 >me >"Jane Smith""#)
    #expect(parsed.directIssueKey == nil)
    #expect(parsed.plainTerms == ["dev-42"])
    #expect(parsed.reporters.isEmpty)
    #expect(parsed.unresolvedShortcuts == [
      .init(kind: .reporter, value: "me", sourceText: ">me"),
      .init(kind: .reporter, value: "Jane Smith", sourceText: #">"Jane Smith""#),
    ])
    #expect(SearchQueryParser().parse(">").plainTerms.isEmpty)
  }

  @Test func reporterCompletionRoundTripsQuotedNames() {
    let shortcut = ResolvedShortcut(
      kind: .reporter, displayName: #"Jane "JJ" Smith"#, canonicalValue: "account-1")
    let parsed = SearchQueryParser().parse(shortcut.insertionText)
    #expect(parsed.unresolvedShortcuts.first?.kind == .reporter)
    #expect(parsed.unresolvedShortcuts.first?.value == shortcut.displayName)
    #expect(shortcut.insertionText(preserving: "jane").hasPrefix(">\"jane"))
  }

  @Test func portableQuotedShortcutIsUnresolvedUntilMetadataResolution() {
    let parsed = SearchQueryParser().parse(#"pdf #"user story""#)

    #expect(parsed.plainTerms == ["pdf"])
    #expect(
      parsed.unresolvedShortcuts == [
        .init(kind: .issueType, value: "user story", sourceText: #"#"user story""#)
      ])
  }

  @Test func plaintextShortcutsStayUnresolvedUntilMetadataResolution() {
    let parsed = SearchQueryParser().parse(#"pdf @DEV #"User Story""#)
    #expect(parsed.plainTerms == ["pdf"])
    #expect(parsed.projects.isEmpty)
    #expect(parsed.issueTypes.isEmpty)
    #expect(parsed.unresolvedShortcuts.map(\.sourceText) == ["@DEV", #"#"User Story""#])
  }

  @Test func issueKeyIsRecognizedCaseInsensitively() {
    let parsed = SearchQueryParser().parse("dev-1234")
    #expect(parsed.directIssueKey == "DEV-1234")
    #expect(parsed.plainTerms.isEmpty)
  }

  @Test func malformedQuoteRemainsPlainText() {
    let parsed = SearchQueryParser().parse(#"#"user story"#)
    #expect(parsed.unresolvedShortcuts.isEmpty)
    #expect(!parsed.plainTerms.isEmpty)
  }

  @Test func shortcutInsertionQuotesNamesWithSpaces() {
    let shortcut = ResolvedShortcut(
      kind: .issueType,
      displayName: "User Story",
      canonicalValue: "10001"
    )
    #expect(shortcut.insertionText == #"#"User Story""#)
  }

  @Test func completionPreservesTypedCasing() {
    let project = ResolvedShortcut(
      kind: .project, displayName: "RE", canonicalValue: "100", detail: "Rhino Entertainment")
    #expect(project.insertionText(preserving: "re") == "@re")
    #expect(project.insertionText(preserving: "rE") == "@rE")
    #expect(project.insertionText(preserving: "r") == "@rE")
    #expect(project.insertionText(preserving: "") == "@RE")
    #expect(project.insertionText(preserving: "entertain") == "@RE")
    #expect(project.insertionText(preserving: "rhino entertainment") == #"@"rhino entertainment""#)
    #expect(project.canonicalValue == "100")

    let type = ResolvedShortcut(kind: .issueType, displayName: "User Story", canonicalValue: "101")
    #expect(type.insertionText(preserving: "user story") == #"#"user story""#)
    #expect(type.insertionText(preserving: "user") == #"#"user Story""#)
  }

  @Test func scopeEditorAddsPortableQueryShortcuts() {
    let editor = SearchQueryScopeEditor()

    let withProject = editor.adding(kind: .project, value: "si", to: "pdf export")
    let withType = editor.adding(kind: .issueType, value: "User Story", to: withProject)

    #expect(withType == #"pdf export @si #"User Story" "#)
  }

  @Test func scopeEditorDoesNotDuplicateAliasesAndCanToggleThemOff() {
    let editor = SearchQueryScopeEditor()
    let input = #"pdf @"Service Improvements" #Epic ~me"#

    #expect(
      editor.adding(
        kind: .project,
        value: "SI",
        aliases: ["Service Improvements"],
        to: input
      ) == input
    )
    #expect(
      editor.removing(
        kind: .project,
        values: ["SI", "Service Improvements"],
        from: input
      ) == "pdf #Epic ~me "
    )
  }

  @Test func scopeEditorClearsOnlyProjectAndIssueTypeShortcuts() {
    let editor = SearchQueryScopeEditor()
    let input = #"pdf @SI #"User Story" ~me >me export"#

    #expect(editor.clearingProjectAndIssueTypeScopes(from: input) == "pdf ~me >me export ")
  }

  @Test func scopeEditorCommitsNewAndRemovedScopesWithSpace() {
    let editor = SearchQueryScopeEditor()

    #expect(editor.adding(kind: .project, value: "ka", to: "ggl") == "ggl @ka ")
    #expect(editor.removing(kind: .issueType, values: ["Epic"], from: "ggl @ka #Epic") == "ggl @ka ")
  }

  @Test func issueReferenceFormatterProducesPlainTextAndSafeHTMLLink() throws {
    let issue = JiraIssue(
      id: "10001",
      key: "DEV-42",
      summary: "Fix <export> & \"sharing\"",
      project: JiraProject(id: "10", key: "DEV", name: "Development"),
      issueType: JiraIssueType(id: "20", name: "Bug"),
      status: JiraStatus(name: "Open", category: .new)
    )
    let formatter = IssueReferenceFormatter()
    let url = try #require(URL(string: "https://example.atlassian.net/browse/DEV-42"))

    #expect(formatter.plainText(for: issue) == "DEV-42: Fix <export> & \"sharing\"")
    #expect(
      formatter.htmlLink(for: issue, url: url)
        == #"<a href="https://example.atlassian.net/browse/DEV-42">DEV-42: Fix &lt;export&gt; &amp; &quot;sharing&quot;</a>"#
    )
  }
}
