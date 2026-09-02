import Foundation

public struct IssueReferenceFormatter: Sendable {
  public init() {}

  public func plainText(for issue: JiraIssue) -> String {
    "\(issue.key): \(issue.summary)"
  }

  public func htmlLink(for issue: JiraIssue, url: URL) -> String {
    let href = escapeHTML(url.absoluteString)
    let label = escapeHTML(plainText(for: issue))
    return #"<a href="\#(href)">\#(label)</a>"#
  }

  private func escapeHTML(_ value: String) -> String {
    value
      .replacingOccurrences(of: "&", with: "&amp;")
      .replacingOccurrences(of: "<", with: "&lt;")
      .replacingOccurrences(of: ">", with: "&gt;")
      .replacingOccurrences(of: "\"", with: "&quot;")
      .replacingOccurrences(of: "'", with: "&#39;")
  }
}
