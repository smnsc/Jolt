import AppKit
import JoltCore
import SwiftUI

private enum SearchFieldMetrics {
  static let editorHeight: CGFloat = 38
  static let font = NSFont.systemFont(ofSize: 17)
  static let textLeadingInset: CGFloat = 39
  static let leadingIconWidth: CGFloat = 16
  static let leadingContentPadding: CGFloat = 11
  static let iconTextSpacing: CGFloat = 12
  static let placeholderVerticalOffset: CGFloat = -1
}

final class SearchTextView: NSTextView {
  var commandHandler: ((SearchEditorCommand) -> Bool)?

  override func insertText(_ insertString: Any, replacementRange: NSRange) {
    let string: String
    if let plainString = insertString as? String {
      string = plainString
    } else if let attributedString = insertString as? NSAttributedString {
      string = attributedString.string
    } else {
      super.insertText(insertString, replacementRange: replacementRange)
      return
    }

    super.insertText(normalizedForSingleLineInsertion(string), replacementRange: replacementRange)
  }

  override func mouseDown(with event: NSEvent) {
    if isInWindowDragRegion(event) {
      window?.performDrag(with: event)
      return
    }
    super.mouseDown(with: event)
  }

  override var textContainerOrigin: NSPoint {
    var origin = super.textContainerOrigin
    guard let layoutManager else { return origin }
    let lineHeight = layoutManager.defaultLineHeight(for: SearchFieldMetrics.font)
    origin.y = max(0, floor((SearchFieldMetrics.editorHeight - lineHeight) / 2))
    return origin
  }

  override func keyDown(with event: NSEvent) {
    if event.keyCode == 48 {
      _ = commandHandler?(.commitSuggestion(appendSpace: true))
      return
    }

    let command: SearchEditorCommand?
    switch event.keyCode {
    case 36 where event.modifierFlags.contains(.option): command = .showActions
    case 36: command = .commitSuggestion(appendSpace: false)
    case 49: command = .commitExactAndInsertSpace
    case 125: command = .moveDown
    case 126: command = .moveUp
    case 124 where
      event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty
        && selectedRange() == NSRange(location: (string as NSString).length, length: 0)
        && !hasMarkedText():
      command = .moveRight
    case 53: command = .escape
    default: command = nil
    }
    if let command, commandHandler?(command) == true { return }
    super.keyDown(with: event)
  }

  private func isInWindowDragRegion(_ event: NSEvent) -> Bool {
    guard event.type == .leftMouseDown, event.clickCount == 1,
      event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty,
      let layoutManager, let textContainer
    else { return false }

    layoutManager.ensureLayout(for: textContainer)
    let usedRect = layoutManager.usedRect(for: textContainer)
    let textEnd = textContainerOrigin.x + usedRect.maxX
    let interactiveEnd = max(textEnd + 8, textContainerOrigin.x + 30)
    let location = convert(event.locationInWindow, from: nil)
    return location.x > interactiveEnd
  }

  private func normalizedForSingleLineInsertion(_ string: String) -> String {
    let lines = string.components(separatedBy: .newlines)
    guard lines.count > 1 else { return string }
    return lines
      .map { $0.trimmingCharacters(in: .whitespaces) }
      .filter { !$0.isEmpty }
      .joined(separator: " ")
  }
}

private final class SearchEditorClipView: NSClipView {
  override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
    var bounds = super.constrainBoundsRect(proposedBounds)
    bounds.origin.y = 0
    return bounds
  }
}

private final class SearchEditorScrollView: NSScrollView {
  override func layout() {
    super.layout()
    guard let textView = documentView as? SearchTextView else { return }

    let viewport = contentSize
    var frame = textView.frame
    frame.origin = .zero
    frame.size.width = max(frame.width, viewport.width)
    frame.size.height = viewport.height
    if frame != textView.frame {
      textView.frame = frame
    }
    let scrollOrigin = contentView.bounds.origin
    if scrollOrigin.y != 0 {
      contentView.scroll(to: NSPoint(x: scrollOrigin.x, y: 0))
    }
    textView.minSize = viewport
    textView.maxSize = NSSize(
      width: CGFloat.greatestFiniteMagnitude,
      height: viewport.height
    )
  }
}

enum SearchEditorCommand {
  case moveUp
  case moveDown
  case moveRight
  case commitSuggestion(appendSpace: Bool)
  case commitExactAndInsertSpace
  case showActions
  case escape
}

struct SearchCompletionRequest: Equatable {
  let id = UUID()
  let text: String
  let appendSpace: Bool
}

struct PlainSearchTextEditor: NSViewRepresentable {
  @Binding var text: String
  let completionRequest: SearchCompletionRequest?
  let onTextChange: (String) -> Void
  let onCompletion: (String) -> Void
  let onContextChange: (AutocompleteContext?) -> Void
  let onCommand: (SearchEditorCommand) -> Bool

  func makeCoordinator() -> Coordinator {
    Coordinator(self)
  }

  func makeNSView(context: Context) -> NSScrollView {
    let scrollView = SearchEditorScrollView()
    let clipView = SearchEditorClipView()
    clipView.drawsBackground = false
    scrollView.contentView = clipView
    scrollView.drawsBackground = false
    scrollView.hasVerticalScroller = false
    scrollView.hasHorizontalScroller = false
    scrollView.verticalScrollElasticity = .none
    scrollView.borderType = .noBorder
    scrollView.automaticallyAdjustsContentInsets = false

    let textView = SearchTextView(
      frame: NSRect(x: 0, y: 0, width: 1, height: SearchFieldMetrics.editorHeight))
    textView.delegate = context.coordinator
    textView.isRichText = false
    textView.importsGraphics = false
    if #available(macOS 15.0, *) {
      textView.writingToolsBehavior = .none
    }
    textView.isContinuousSpellCheckingEnabled = false
    textView.isGrammarCheckingEnabled = false
    textView.isAutomaticSpellingCorrectionEnabled = false
    textView.isAutomaticQuoteSubstitutionEnabled = false
    textView.isAutomaticDashSubstitutionEnabled = false
    textView.isAutomaticTextReplacementEnabled = false
    textView.isAutomaticLinkDetectionEnabled = false
    textView.isAutomaticDataDetectionEnabled = false
    textView.drawsBackground = false
    textView.font = SearchFieldMetrics.font
    textView.textColor = .labelColor
    textView.insertionPointColor = .labelColor
    textView.typingAttributes = [
      .font: SearchFieldMetrics.font,
      .foregroundColor: NSColor.labelColor,
    ]
    textView.textContainerInset = NSSize(width: SearchFieldMetrics.textLeadingInset, height: 0)
    textView.isVerticallyResizable = false
    textView.isHorizontallyResizable = true
    textView.textContainer?.containerSize = NSSize(
      width: CGFloat.greatestFiniteMagnitude,
      height: SearchFieldMetrics.editorHeight
    )
    textView.textContainer?.widthTracksTextView = false
    textView.textContainer?.heightTracksTextView = true
    textView.textContainer?.lineFragmentPadding = 0
    textView.textContainer?.maximumNumberOfLines = 1
    textView.textContainer?.lineBreakMode = .byClipping
    textView.autoresizingMask = [.height]
    textView.commandHandler = onCommand
    scrollView.documentView = textView
    context.coordinator.textView = textView
    context.coordinator.apply(text)

    NotificationCenter.default.addObserver(
      context.coordinator,
      selector: #selector(Coordinator.focus),
      name: .focusSearchField,
      object: nil
    )
    return scrollView
  }

  func updateNSView(_ scrollView: NSScrollView, context: Context) {
    context.coordinator.parent = self
    guard let textView = context.coordinator.textView else { return }
    textView.commandHandler = onCommand
    scrollView.layoutSubtreeIfNeeded()

    if context.coordinator.lastCompletionID != completionRequest?.id, let completionRequest {
      context.coordinator.lastCompletionID = completionRequest.id
      context.coordinator.insert(completionRequest)
    } else if textView.string != text {
      context.coordinator.apply(text)
    }
  }

  final class Coordinator: NSObject, NSTextViewDelegate {
    var parent: PlainSearchTextEditor
    weak var textView: SearchTextView?
    var activeRange: NSRange?
    var lastCompletionID: UUID?
    private var isApplying = false

    init(_ parent: PlainSearchTextEditor) {
      self.parent = parent
    }

    deinit {
      NotificationCenter.default.removeObserver(self)
    }

    @objc func focus() {
      guard let textView, textView.window?.isKeyWindow == true else { return }
      textView.window?.makeFirstResponder(textView)
    }

    func textDidChange(_ notification: Notification) {
      guard !isApplying, let textView else { return }
      enforcePlainTextAppearance(in: textView)
      parent.text = textView.string
      parent.onTextChange(textView.string)
      updateContext()
    }

    func textViewDidChangeSelection(_ notification: Notification) {
      updateContext()
    }

    func apply(_ text: String) {
      guard let textView else { return }
      isApplying = true
      textView.string = text
      enforcePlainTextAppearance(in: textView)
      textView.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
      isApplying = false
      updateContext()
    }

    func insert(_ request: SearchCompletionRequest) {
      guard let textView, let activeRange else { return }
      let replacement = request.text + (request.appendSpace ? " " : "")
      textView.insertText(replacement, replacementRange: activeRange)
      textView.window?.makeFirstResponder(textView)
      self.activeRange = nil
      parent.onContextChange(nil)
      parent.onCompletion(textView.string)
    }

    private func enforcePlainTextAppearance(in textView: NSTextView) {
      let attributes: [NSAttributedString.Key: Any] = [
        .font: SearchFieldMetrics.font,
        .foregroundColor: NSColor.labelColor,
      ]
      textView.font = SearchFieldMetrics.font
      textView.textColor = .labelColor
      textView.typingAttributes = attributes
      if let storage = textView.textStorage, storage.length > 0 {
        storage.setAttributes(attributes, range: NSRange(location: 0, length: storage.length))
      }
    }

    private func updateContext() {
      guard let textView else { return }
      let caret = textView.selectedRange().location
      guard caret <= (textView.string as NSString).length else { return }
      let beforeCaret = (textView.string as NSString).substring(to: caret)
      let pattern = #"(?<!\S)([@#~>])(?:\"([^\"]*)|([^\s]*))$"#
      guard let expression = try? NSRegularExpression(pattern: pattern),
        let match = expression.firstMatch(
          in: beforeCaret, range: NSRange(location: 0, length: (beforeCaret as NSString).length)),
        let prefixRange = Range(match.range(at: 1), in: beforeCaret),
        let prefix = beforeCaret[prefixRange].first,
        let kind = SearchShortcutKind(prefix: prefix)
      else {
        activeRange = nil
        parent.onContextChange(nil)
        return
      }
      let queryRange =
        match.range(at: 2).location != NSNotFound ? match.range(at: 2) : match.range(at: 3)
      let query = Range(queryRange, in: beforeCaret).map { String(beforeCaret[$0]) } ?? ""
      activeRange = match.range
      parent.onContextChange(.init(kind: kind, query: query))
    }
  }
}

struct SearchField: View {
  @EnvironmentObject private var model: AppModel
  @State private var text = ""
  @State private var completionRequest: SearchCompletionRequest?

  var body: some View {
    PlainSearchTextEditor(
      text: $text,
      completionRequest: completionRequest,
      onTextChange: model.inputDidChange,
      onCompletion: model.inputDidCompleteShortcut,
      onContextChange: model.updateAutocomplete,
      onCommand: handleCommand
    )
    .frame(height: SearchFieldMetrics.editorHeight)
    .contentShape(Rectangle())
    .overlay(alignment: .leading) {
      HStack(spacing: SearchFieldMetrics.iconTextSpacing) {
        Group {
          if model.isSearching {
            ProgressView()
              .controlSize(.small)
              .accessibilityLabel("Searching Jira")
          } else {
            Image(systemName: "magnifyingglass")
              .font(.system(size: 15, weight: .medium))
              .foregroundStyle(.secondary)
          }
        }
        .frame(
          width: SearchFieldMetrics.leadingIconWidth,
          height: SearchFieldMetrics.leadingIconWidth
        )
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
          Text("Search issues by text, @project, #type, ~assignee, >reporter…")
            .font(.system(size: 17))
            .foregroundStyle(.tertiary)
            .offset(y: SearchFieldMetrics.placeholderVerticalOffset)
        }
      }
      .padding(.leading, SearchFieldMetrics.leadingContentPadding)
      .allowsHitTesting(false)
    }
    .overlay(alignment: .topLeading) {
      if model.autocompleteContext != nil, !model.autocompleteSuggestions.isEmpty {
        suggestionList
          .offset(y: 40)
          .zIndex(100)
      }
    }
    .onChange(of: model.input) { _, newValue in
      if newValue != text { text = newValue }
    }
    .onAppear {
      text = model.input
      // The editor can be inserted after the window's didBecomeKey notification (for example,
      // after authentication or when returning from issue preview). Focus it once SwiftUI has
      // attached its AppKit view to the key window.
      DispatchQueue.main.async {
        NotificationCenter.default.post(name: .focusSearchField, object: nil)
      }
    }
  }

  private var suggestionList: some View {
    VStack(spacing: 2) {
      ForEach(Array(model.autocompleteSuggestions.prefix(8).enumerated()), id: \.element.id) {
        index, suggestion in
        Button {
          completionRequest = .init(text: suggestion.insertionText(preserving: model.autocompleteContext?.query ?? ""), appendSpace: true)
        } label: {
          HStack {
            Text(String(suggestion.kind.prefix))
              .foregroundStyle(.secondary)
            Text(suggestion.displayName)
            if let detail = suggestion.detail {
              Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            Spacer()
          }
          .padding(.horizontal, 10)
          .padding(.vertical, 6)
          .background(
            index == model.autocompleteSelection ? Color.accentColor.opacity(0.18) : Color.clear
          )
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
      }
    }
    .padding(4)
    .frame(width: 330)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
    .overlay(
      RoundedRectangle(cornerRadius: 10)
        .stroke(Color(nsColor: .separatorColor).opacity(0.5))
    )
    .shadow(radius: 12, y: 5)
  }

  private func handleCommand(_ command: SearchEditorCommand) -> Bool {
    if model.isActionsMenuPresented {
      switch command {
      case .moveUp:
        model.moveIssueAction(by: -1)
      case .moveDown:
        model.moveIssueAction(by: 1)
      case .moveRight:
        return true
      case .commitSuggestion(let appendSpace):
        if !appendSpace { model.performSelectedIssueAction() }
      case .showActions:
        model.dismissActionsMenu()
      case .escape:
        model.dismissActionsMenu()
      case .commitExactAndInsertSpace:
        return true
      }
      return true
    }

    let hasAutocomplete = model.autocompleteContext != nil && !model.autocompleteSuggestions.isEmpty
    switch command {
    case .moveUp where hasAutocomplete:
      model.autocompleteSelection = max(0, model.autocompleteSelection - 1)
      return true
    case .moveDown where hasAutocomplete:
      model.autocompleteSelection = min(
        model.autocompleteSuggestions.count - 1, model.autocompleteSelection + 1)
      return true
    case .moveRight where hasAutocomplete:
      return false
    case .commitSuggestion where hasAutocomplete:
      let index = min(model.autocompleteSelection, model.autocompleteSuggestions.count - 1)
      completionRequest = .init(
        text: model.autocompleteSuggestions[index].insertionText(
          preserving: model.autocompleteContext?.query ?? ""),
        appendSpace: true
      )
      return true
    case .commitExactAndInsertSpace:
      guard let context = model.autocompleteContext else { return false }
      if let exact = model.autocompleteSuggestions.first(where: {
        $0.displayName.caseInsensitiveCompare(context.query) == .orderedSame
          || $0.canonicalValue.caseInsensitiveCompare(context.query) == .orderedSame
      }) {
        completionRequest = .init(text: exact.insertionText(preserving: context.query), appendSpace: true)
        return true
      }
      return false
    case .showActions:
      model.presentActionsMenu()
      return true
    case .moveUp:
      model.moveResult(by: -1)
      return true
    case .moveDown:
      model.moveResult(by: 1)
      return true
    case .moveRight:
      model.presentIssuePreview()
      return true
    case .commitSuggestion(let appendSpace):
      if appendSpace { return false }
      model.openSelectedIssue()
      return true
    case .escape:
      model.handleSearchEscape()
      return true
    }
  }
}
