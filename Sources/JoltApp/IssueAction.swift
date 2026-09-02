import Foundation

enum IssueAction: Int, CaseIterable, Identifiable {
  case openInBrowser
  case copyKeyAndTitle
  case copyHTMLLink

  var id: Int { rawValue }

  var title: String {
    switch self {
    case .openInBrowser: return "Open in Browser"
    case .copyKeyAndTitle: return "Copy Issue Key and Title"
    case .copyHTMLLink: return "Copy HTML Formatted Link"
    }
  }

  var systemImage: String {
    switch self {
    case .openInBrowser: return "safari"
    case .copyKeyAndTitle: return "doc.on.doc"
    case .copyHTMLLink: return "link"
    }
  }
}
