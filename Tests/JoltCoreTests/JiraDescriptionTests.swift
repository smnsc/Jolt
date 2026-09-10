import Foundation
import Testing
@testable import JoltCore

struct JiraDescriptionTests {
  @Test func preservesDocumentFormatting() throws {
    let json = #"{"type":"doc","version":1,"content":[{"type":"heading","attrs":{"level":2},"content":[{"type":"text","text":"Title","marks":[{"type":"strong"}]}]},{"type":"orderedList","attrs":{"order":3},"content":[{"type":"listItem","content":[{"type":"paragraph","content":[{"type":"text","text":"Link","marks":[{"type":"link","attrs":{"href":"https://example.com"}},{"type":"em"}]}]}]}]},{"type":"codeBlock","attrs":{"language":"swift"},"content":[{"type":"text","text":"let x = 1\nprint(x)"}]}]}"#
    let document = try JSONDecoder().decode(JiraDescription.self, from: Data(json.utf8))
    #expect(!document.isEmpty)
    #expect(document.content?[0].attrs?.level == 2)
    #expect(document.content?[0].content?[0].marks?[0].type == "strong")
    #expect(document.content?[1].attrs?.order == 3)
    let link = document.content?[1].content?[0].content?[0].content?[0]
    #expect(link?.marks?[0].attrs?.href == "https://example.com")
    #expect(link?.marks?[1].type == "em")
    #expect(document.content?[2].content?[0].text == "let x = 1\nprint(x)")
  }

  @Test func supportsPlainStringsAndEmptyDocuments() throws {
    let decoder = JSONDecoder()
    let plain = try decoder.decode(JiraDescription.self, from: Data(#""Literal *text*""#.utf8))
    #expect(plain.text == "Literal *text*")
    #expect(!plain.isEmpty)
    let empty = try decoder.decode(JiraDescription.self, from: Data(#"{"type":"doc","content":[{"type":"paragraph"}]}"#.utf8))
    #expect(empty.isEmpty)
  }

  @Test func preservesUnknownNodeChildrenAndAttachments() throws {
    let decoder = JSONDecoder()
    let unknown = try decoder.decode(JiraDescription.self, from: Data(#"{"type":"futureNode","attrs":{"unknown":true},"content":[{"type":"text","text":"Still readable"}]}"#.utf8))
    #expect(!unknown.isEmpty)
    #expect(unknown.content?.first?.text == "Still readable")
    let media = try decoder.decode(JiraDescription.self, from: Data(#"{"type":"mediaSingle","content":[{"type":"media","attrs":{"id":"example"}}]}"#.utf8))
    #expect(!media.isEmpty)
  }
}
