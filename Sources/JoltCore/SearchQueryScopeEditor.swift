import Foundation

/// Adds and removes scope-bar shortcuts while keeping the search field as one plain string.
public struct SearchQueryScopeEditor: Sendable {
  public init() {}

  public func contains(
    kind: SearchShortcutKind,
    values: [String],
    in text: String
  ) -> Bool {
    let candidates = Set(values.map(normalized))
    return shortcuts(in: text).contains {
      $0.kind == kind && candidates.contains(normalized($0.value))
    }
  }

  public func adding(
    kind: SearchShortcutKind,
    value: String,
    aliases: [String] = [],
    to text: String
  ) -> String {
    guard !contains(kind: kind, values: [value] + aliases, in: text) else { return text }
    let insertion = ResolvedShortcut(
      kind: kind,
      displayName: value,
      canonicalValue: value
    ).insertionText
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    return committed(trimmed.isEmpty ? insertion : "\(trimmed) \(insertion)")
  }

  public func removing(
    kind: SearchShortcutKind,
    values: [String],
    from text: String
  ) -> String {
    let candidates = Set(values.map(normalized))
    return removingShortcuts(from: text) {
      $0.kind == kind && candidates.contains(normalized($0.value))
    }
  }

  public func clearingProjectAndIssueTypeScopes(from text: String) -> String {
    removingShortcuts(from: text) { shortcut in
      shortcut.kind == .project || shortcut.kind == .issueType
    }
  }

  private struct ShortcutToken {
    let kind: SearchShortcutKind
    let value: String
    let removalRange: Range<String.Index>
  }

  private func removingShortcuts(
    from text: String,
    where shouldRemove: (ShortcutToken) -> Bool
  ) -> String {
    let removals = shortcuts(in: text).filter(shouldRemove)
    guard !removals.isEmpty else { return text }

    var result = ""
    var cursor = text.startIndex
    for token in removals {
      result.append(contentsOf: text[cursor..<token.removalRange.lowerBound])
      cursor = token.removalRange.upperBound
    }
    result.append(contentsOf: text[cursor..<text.endIndex])
    return committed(result)
  }

  private func shortcuts(in text: String) -> [ShortcutToken] {
    var output: [ShortcutToken] = []
    var index = text.startIndex

    while index < text.endIndex {
      let separatorStart = index
      while index < text.endIndex, text[index].isWhitespace {
        index = text.index(after: index)
      }
      guard index < text.endIndex else { break }

      guard let kind = SearchShortcutKind(prefix: text[index]) else {
        while index < text.endIndex, !text[index].isWhitespace {
          index = text.index(after: index)
        }
        continue
      }

      index = text.index(after: index)
      var value = ""
      if index < text.endIndex, text[index] == "\"" {
        index = text.index(after: index)
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
        guard didClose, !value.isEmpty else { continue }
      } else {
        while index < text.endIndex, !text[index].isWhitespace {
          value.append(text[index])
          index = text.index(after: index)
        }
        guard !value.isEmpty else { continue }
      }

      output.append(
        ShortcutToken(
          kind: kind,
          value: value,
          removalRange: separatorStart..<index
        ))

    }

    return output
  }

  private func normalized(_ value: String) -> String {
    value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
  }

  private func committed(_ text: String) -> String {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? "" : "\(trimmed) "
  }
}
