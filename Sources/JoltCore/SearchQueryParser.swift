import Foundation

public struct SearchQueryParser: Sendable {
  public init() {}

  public func parse(_ text: String) -> ParsedSearch {
    var result = ParsedSearch()

    for lexeme in lex(text) {
      switch lexeme {
      case .plain(let term):
        if isIssueKey(term) {
          result.plainTerms.append(term)
        } else {
          result.plainTerms.append(contentsOf: splitPlainTerm(term))
        }
      case .shortcut(let shortcut):
        result.unresolvedShortcuts.append(shortcut)
      }
    }

    if result.projects.isEmpty,
      result.issueTypes.isEmpty,
      result.assignees.isEmpty,
      result.reporters.isEmpty,
      result.unresolvedShortcuts.isEmpty,
      result.plainTerms.count == 1,
      isIssueKey(result.plainTerms[0])
    {
      result.directIssueKey = result.plainTerms[0].uppercased()
      result.plainTerms.removeAll()
    }

    return result
  }

  private enum Lexeme {
    case plain(String)
    case shortcut(UnresolvedShortcut)
  }

  private func lex(_ text: String) -> [Lexeme] {
    var output: [Lexeme] = []
    var index = text.startIndex

    while index < text.endIndex {
      while index < text.endIndex, text[index].isWhitespace {
        index = text.index(after: index)
      }
      guard index < text.endIndex else { break }

      let start = index
      let first = text[index]
      if let kind = SearchShortcutKind(prefix: first) {
        index = text.index(after: index)
        if index < text.endIndex, text[index] == "\"" {
          index = text.index(after: index)
          var value = ""
          var escaped = false
          var didClose = false
          while index < text.endIndex {
            let character = text[index]
            index = text.index(after: index)
            if escaped {
              value.append(character)
              escaped = false
            } else if character == "\\" {
              escaped = true
            } else if character == "\"" {
              didClose = true
              break
            } else {
              value.append(character)
            }
          }
          if didClose, !value.isEmpty {
            let source = String(text[start..<index])
            output.append(.shortcut(.init(kind: kind, value: value, sourceText: source)))
          } else {
            output.append(.plain(String(text[start..<index])))
          }
        } else {
          while index < text.endIndex, !text[index].isWhitespace {
            index = text.index(after: index)
          }
          let source = String(text[start..<index])
          let value = String(source.dropFirst())
          if value.isEmpty {
            output.append(.plain(source))
          } else {
            output.append(.shortcut(.init(kind: kind, value: value, sourceText: source)))
          }
        }
      } else {
        while index < text.endIndex, !text[index].isWhitespace {
          index = text.index(after: index)
        }
        output.append(.plain(String(text[start..<index])))
      }
    }

    return output
  }

  private func splitPlainTerm(_ term: String) -> [String] {
    let separators = CharacterSet(charactersIn: "-+!*&|(){}[]^~?:\\/\"")
    return term.components(separatedBy: separators)
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty && $0 != "@" && $0 != "#" && $0 != "~" && $0 != ">" }
  }

  private func isIssueKey(_ value: String) -> Bool {
    value.range(of: #"^[A-Za-z][A-Za-z0-9_]*-[0-9]+$"#, options: .regularExpression) != nil
  }
}
