import Foundation

/// Jira's structured document, retained intact until the preview renders it.
public struct JiraDescription: Decodable, Sendable {
  public let type: String
  public let text: String?
  public let content: [JiraDescription]?
  public let attrs: Attributes?
  public let marks: [Mark]?

  public struct Attributes: Decodable, Sendable {
    public let text: String?
    public let shortName: String?
    public let url: String?
    public let href: String?
    public let level: Int?
    public let order: Int?
    public let language: String?
  }

  public struct Mark: Decodable, Sendable {
    public let type: String
    public let attrs: Attributes?
  }

  public init(from decoder: Decoder) throws {
    if let string = try? decoder.singleValueContainer().decode(String.self) {
      type = "text"
      text = string
      content = nil
      attrs = nil
      marks = nil
      return
    }
    let values = try decoder.container(keyedBy: CodingKeys.self)
    type = try values.decode(String.self, forKey: .type)
    text = try values.decodeIfPresent(String.self, forKey: .text)
    content = try values.decodeIfPresent([Self].self, forKey: .content)
    attrs = try values.decodeIfPresent(Attributes.self, forKey: .attrs)
    marks = try values.decodeIfPresent([Mark].self, forKey: .marks)
  }

  public var isEmpty: Bool {
    switch type {
    case "rule", "media", "mediaSingle", "mediaGroup": return false
    default:
      return (text ?? attrs?.text ?? attrs?.shortName ?? attrs?.url ?? "")
        .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && (content ?? []).allSatisfy(\.isEmpty)
    }
  }

  private enum CodingKeys: String, CodingKey {
    case type, text, content, attrs, marks
  }
}
