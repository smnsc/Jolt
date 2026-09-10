import SwiftUI
import JoltCore

/// Render ADF directly, so literal text cannot accidentally become Markdown syntax.
struct IssueDescriptionView: View {
  let node: JiraDescription

  var body: some View {
    block(node)
      .font(.system(size: 15))
      .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func children(_ node: JiraDescription) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      ForEach(Array((node.content ?? []).enumerated()), id: \.offset) { _, child in
        block(child)
      }
    }
  }

  private func block(_ node: JiraDescription) -> AnyView {
    switch node.type {
    case "doc", "listItem", "tableCell":
      return AnyView(children(node))
    case "paragraph", "text", "heading":
      let size: CGFloat = node.type == "heading"
        ? [26, 23, 20, 18, 16, 15][min(6, max(1, node.attrs?.level ?? 1)) - 1] : 15
      return AnyView(Text(inline(node))
        .font(.system(size: size, weight: node.type == "heading" ? .bold : .regular))
        .lineSpacing(4).frame(maxWidth: .infinity, alignment: .leading))
    case "bulletList", "orderedList":
      return AnyView(VStack(alignment: .leading, spacing: 6) {
        ForEach(Array((node.content ?? []).enumerated()), id: \.offset) { index, item in
          HStack(alignment: .top, spacing: 8) {
            Text(node.type == "bulletList" ? "•" : "\((node.attrs?.order ?? 1) + index).")
              .monospacedDigit().frame(minWidth: 20, alignment: .trailing)
            block(item).frame(maxWidth: .infinity, alignment: .leading)
          }
        }
      })
    case "blockquote", "panel":
      return AnyView(HStack(alignment: .top, spacing: 12) {
        Rectangle().fill(Color.secondary.opacity(0.4)).frame(width: 3)
        children(node)
      }.fixedSize(horizontal: false, vertical: true).padding(.vertical, 4))
    case "codeBlock":
      return AnyView(ScrollView(.horizontal) {
        Text(rawText(node)).font(.system(size: 13, design: .monospaced))
          .padding(12).frame(maxWidth: .infinity, alignment: .leading)
      }.background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6)))
    case "table":
      return AnyView(ScrollView(.horizontal) {
        Grid(alignment: .topLeading, horizontalSpacing: 0, verticalSpacing: 0) {
          ForEach(Array((node.content ?? []).enumerated()), id: \.offset) { _, row in
            GridRow {
              ForEach(Array((row.content ?? []).enumerated()), id: \.offset) { _, cell in
                children(cell).fontWeight(cell.type == "tableHeader" ? .bold : .regular)
                  .padding(8).frame(minWidth: 120, maxWidth: 300, alignment: .leading)
                  .background(Color.secondary.opacity(cell.type == "tableHeader" ? 0.12 : 0.04))
                  .border(Color.secondary.opacity(0.2))
              }
            }
          }
        }
      })
    case "rule": return AnyView(Divider())
    case "media", "mediaSingle", "mediaGroup":
      return AnyView(Label("Attachment — open in Jira to view", systemImage: "paperclip").foregroundStyle(.secondary))
    default:
      if !(node.content ?? []).isEmpty { return AnyView(children(node)) }
      return AnyView(Text(inline(node)))
    }
  }

  private func rawText(_ node: JiraDescription) -> String {
    if node.type == "hardBreak" { return "\n" }
    return node.text ?? (node.content ?? []).map(rawText).joined()
  }

  private func inline(_ node: JiraDescription) -> AttributedString {
    var result: AttributedString
    switch node.type {
    case "hardBreak": result = AttributedString("\n")
    case "mention": result = AttributedString(node.attrs?.text ?? "")
    case "emoji": result = AttributedString(node.attrs?.text ?? node.attrs?.shortName ?? "")
    case "inlineCard", "blockCard":
      result = AttributedString(node.attrs?.url ?? "")
      result.link = safeURL(node.attrs?.url)
    default:
      result = AttributedString(node.text ?? "")
      for child in node.content ?? [] { result.append(inline(child)) }
    }
    for mark in node.marks ?? [] {
      switch mark.type {
      case "strong": result.inlinePresentationIntent = (result.inlinePresentationIntent ?? []).union(.stronglyEmphasized)
      case "em": result.inlinePresentationIntent = (result.inlinePresentationIntent ?? []).union(.emphasized)
      case "strike": result.strikethroughStyle = .single
      case "underline": result.underlineStyle = .single
      case "code": result.font = .system(size: 13, design: .monospaced)
      case "link": result.link = safeURL(mark.attrs?.href)
      default: break
      }
    }
    return result
  }

  private func safeURL(_ value: String?) -> URL? {
    guard let value, let url = URL(string: value),
          ["https", "http", "mailto"].contains(url.scheme?.lowercased() ?? "") else { return nil }
    return url
  }
}
