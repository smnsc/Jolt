import Foundation
import JoltCore

protocol JiraServing: AnyObject {
  func setSite(_ site: JiraSite) async
  func search(jql: String, maxResults: Int) async throws -> [JiraIssue]
  func issueDescription(issueID: String) async throws -> JiraDescription?
  func projects() async throws -> [JiraProject]
  func issueTypes() async throws -> [JiraIssueType]
  func suggestions(field: String, value: String) async throws -> [JiraAutocompleteSuggestion]
  func data(from url: URL) async throws -> Data
}

actor JiraClient: JiraServing {
  private let auth: JiraAuthSession
  private let urlSession: URLSession
  private var site: JiraSite?

  init(auth: JiraAuthSession, urlSession: URLSession = .shared) {
    self.auth = auth
    self.urlSession = urlSession
  }

  func setSite(_ site: JiraSite) {
    self.site = site
  }

  func search(jql: String, maxResults: Int) async throws -> [JiraIssue] {
    let body: [String: Any] = [
      "jql": jql,
      "maxResults": maxResults,
      "fields": ["summary", "project", "issuetype", "status"],
    ]
    let data = try JSONSerialization.data(withJSONObject: body)
    let responseData = try await request(path: "/rest/api/3/search/jql", method: "POST", body: data)
    let response = try JSONDecoder().decode(SearchResponse.self, from: responseData)
    return response.issues.map(\.model)
  }

  func issueDescription(issueID: String) async throws -> JiraDescription? {
    let pathCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
    guard let encodedIssueID = issueID.addingPercentEncoding(withAllowedCharacters: pathCharacters)
    else { throw AppError.invalidResponse }
    let data = try await request(
      path: "/rest/api/3/issue/\(encodedIssueID)",
      query: [.init(name: "fields", value: "description")]
    )
    let response = try JSONDecoder().decode(IssueDescriptionResponse.self, from: data)
    return response.fields.description
  }

  func projects() async throws -> [JiraProject] {
    var projects: [JiraProject] = []
    var startAt = 0
    repeat {
      let data = try await request(
        path: "/rest/api/3/project/search",
        query: [
          .init(name: "startAt", value: String(startAt)),
          .init(name: "maxResults", value: "100"),
          .init(name: "orderBy", value: "name"),
        ]
      )
      let page = try JSONDecoder().decode(ProjectPage.self, from: data)
      projects.append(contentsOf: page.values)
      startAt += page.values.count
      if page.isLast == true || page.values.isEmpty { break }
      if let total = page.total, startAt >= total { break }
    } while true
    return projects
  }

  func issueTypes() async throws -> [JiraIssueType] {
    let data = try await request(path: "/rest/api/3/issuetype")
    return try JSONDecoder().decode([JiraIssueType].self, from: data)
  }

  func suggestions(field: String, value: String) async throws -> [JiraAutocompleteSuggestion] {
    let data = try await request(
      path: "/rest/api/3/jql/autocompletedata/suggestions",
      query: [
        .init(name: "fieldName", value: field),
        .init(name: "fieldValue", value: value),
      ]
    )
    let response = try JSONDecoder().decode(SuggestionResponse.self, from: data)
    return response.results.map {
      .init(displayName: $0.displayName.removingHTMLTags, value: $0.value)
    }
  }

  func data(from url: URL) async throws -> Data {
    let selectedHost = site?.url.host?.lowercased()
    let sourceHost = url.host?.lowercased()
    var requestURL = url
    var requiresAuthorization = false

    if let site, sourceHost == selectedHost {
      var components = URLComponents(
        string: "https://api.atlassian.com/ex/jira/\(site.id)\(url.path)")
      components?.percentEncodedQuery =
        URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedQuery
      guard let proxiedURL = components?.url else { throw AppError.invalidResponse }
      requestURL = proxiedURL
      requiresAuthorization = true
    } else if let site, sourceHost == "api.atlassian.com",
      url.path.hasPrefix("/ex/jira/\(site.id)/")
    {
      requiresAuthorization = true
    }

    var request = URLRequest(url: requestURL)
    if requiresAuthorization {
      request.setValue(try await auth.authorizationHeader(), forHTTPHeaderField: "Authorization")
    }
    let (data, response) = try await urlSession.data(for: request)
    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
      throw AppError.invalidResponse
    }
    return data
  }

  private func request(
    path: String,
    method: String = "GET",
    query: [URLQueryItem] = [],
    body: Data? = nil
  ) async throws -> Data {
    guard let site else { throw AppError.noJiraSites }
    guard var components = URLComponents(
      string: "https://api.atlassian.com/ex/jira/\(site.id)\(path)")
    else { throw AppError.invalidResponse }
    components.queryItems = query.isEmpty ? nil : query
    guard let url = components.url else { throw AppError.invalidResponse }

    var request = URLRequest(url: url)
    request.httpMethod = method
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.setValue(try await auth.authorizationHeader(), forHTTPHeaderField: "Authorization")
    if let body {
      request.httpBody = body
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    }

    let (data, response) = try await urlSession.data(for: request)
    guard let http = response as? HTTPURLResponse else { throw AppError.invalidResponse }
    guard (200..<300).contains(http.statusCode) else {
      var message = JiraAuthSession.errorMessage(from: data)
      if http.statusCode == 429, let retry = http.value(forHTTPHeaderField: "Retry-After") {
        message = "Rate limited. Try again in \(retry) seconds."
      }
      throw AppError.server(status: http.statusCode, message: message)
    }
    return data
  }
}

private struct SearchResponse: Decodable {
  let issues: [IssueDTO]
}

private struct IssueDTO: Decodable {
  let id: String
  let key: String
  let fields: Fields

  struct Fields: Decodable {
    let summary: String
    let project: JiraProject
    let issuetype: JiraIssueType
    let status: StatusDTO
  }

  struct StatusDTO: Decodable {
    let name: String
    let statusCategory: CategoryDTO
  }

  struct CategoryDTO: Decodable {
    let key: JiraStatusCategory
  }

  var model: JiraIssue {
    JiraIssue(
      id: id,
      key: key,
      summary: fields.summary,
      project: fields.project,
      issueType: fields.issuetype,
      status: .init(name: fields.status.name, category: fields.status.statusCategory.key)
    )
  }
}

private struct IssueDescriptionResponse: Decodable {
  let fields: Fields

  struct Fields: Decodable {
    let description: JiraDescription?
  }
}

private struct ProjectPage: Decodable {
  let values: [JiraProject]
  let total: Int?
  let isLast: Bool?
}

private struct SuggestionResponse: Decodable {
  let results: [JiraAutocompleteSuggestion]
}

extension String {
  fileprivate var removingHTMLTags: String {
    replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
      .replacingOccurrences(of: "&amp;", with: "&")
      .replacingOccurrences(of: "&quot;", with: "\"")
      .replacingOccurrences(of: "&#39;", with: "'")
  }
}
