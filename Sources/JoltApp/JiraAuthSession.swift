import Foundation
import JoltCore

private struct JiraAPICredentials: Codable, Sendable {
  let site: JiraSite
  let email: String
  let apiKey: String
}

private struct JiraTenantInfo: Decodable {
  let cloudId: String
}

actor JiraAuthSession {
  private let credentials: CredentialStoring
  private let urlSession: URLSession
  private let credentialKey = "atlassian.api.credentials"
  private var cachedCredentials: JiraAPICredentials?

  init(credentials: CredentialStoring = KeychainCredentialStore(), urlSession: URLSession = .shared)
  {
    self.credentials = credentials
    self.urlSession = urlSession
    self.cachedCredentials = try? credentials.codableValue(
      JiraAPICredentials.self, for: credentialKey)
  }

  var isAuthenticated: Bool {
    cachedCredentials != nil
  }

  var site: JiraSite? {
    cachedCredentials?.site
  }

  func connect(siteURL: String, email: String, apiKey: String) async throws -> JiraSite {
    let siteURL = try Self.normalizedSiteURL(siteURL)
    let email = email.trimmingCharacters(in: .whitespacesAndNewlines)
    let apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)

    guard email.contains("@") else { throw AppError.invalidEmail }
    guard !apiKey.isEmpty else { throw AppError.missingAPIKey }

    let authorization = Self.basicAuthorization(email: email, apiKey: apiKey)
    let cloudID = try await cloudID(for: siteURL)
    try await validate(cloudID: cloudID, authorization: authorization)
    try Task.checkCancellation()
    let host = siteURL.host ?? siteURL.absoluteString
    let fallbackName = host.split(separator: ".").first.map(String.init) ?? host
    let site = JiraSite(id: cloudID, url: siteURL, name: fallbackName)
    let newCredentials = JiraAPICredentials(site: site, email: email, apiKey: apiKey)

    try credentials.setCodableValue(newCredentials, for: credentialKey)
    cachedCredentials = newCredentials
    return site
  }

  func authorizationHeader() throws -> String {
    guard let cachedCredentials else { throw AppError.notAuthenticated }
    return Self.basicAuthorization(email: cachedCredentials.email, apiKey: cachedCredentials.apiKey)
  }

  func logout() throws {
    cachedCredentials = nil
    try credentials.remove(credentialKey)
  }

  private func cloudID(for siteURL: URL) async throws -> String {
    guard let url = URL(string: "/_edge/tenant_info", relativeTo: siteURL)?.absoluteURL else {
      throw AppError.invalidJiraSiteURL
    }
    let (data, response) = try await urlSession.data(from: url)
    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
      let tenant = try? JSONDecoder().decode(JiraTenantInfo.self, from: data),
      !tenant.cloudId.isEmpty
    else { throw AppError.invalidJiraSiteURL }
    return tenant.cloudId
  }

  private func validate(cloudID: String, authorization: String) async throws {
    guard let url = URL(
      string: "https://api.atlassian.com/ex/jira/\(cloudID)/rest/api/3/project/search?maxResults=1")
    else { throw AppError.invalidResponse }
    var request = URLRequest(url: url)
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.setValue(authorization, forHTTPHeaderField: "Authorization")

    let (data, response) = try await urlSession.data(for: request)
    guard let http = response as? HTTPURLResponse else { throw AppError.invalidResponse }
    if http.statusCode == 401 || http.statusCode == 403 {
      throw AppError.invalidAPICredentials
    }
    guard (200..<300).contains(http.statusCode) else {
      throw AppError.server(
        status: http.statusCode, message: Self.errorMessage(from: data))
    }
  }

  private static func normalizedSiteURL(_ input: String) throws -> URL {
    var value = input.trimmingCharacters(in: .whitespacesAndNewlines)
    if !value.contains("://") { value = "https://\(value)" }

    guard var components = URLComponents(string: value),
      components.scheme?.lowercased() == "https",
      components.user == nil,
      components.password == nil,
      components.port == nil,
      let host = components.host?.lowercased(),
      host.hasSuffix(".atlassian.net"),
      host != "atlassian.net",
      components.query == nil,
      components.fragment == nil,
      components.path.isEmpty || components.path == "/"
    else {
      throw AppError.invalidJiraSiteURL
    }

    components.scheme = "https"
    components.host = host
    components.path = "/"
    guard let url = components.url else { throw AppError.invalidJiraSiteURL }
    return url
  }

  private static func basicAuthorization(email: String, apiKey: String) -> String {
    "Basic \(Data("\(email):\(apiKey)".utf8).base64EncodedString())"
  }

  static func errorMessage(from data: Data) -> String {
    if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
      if let message = object["message"] as? String { return message }
      if let description = object["error_description"] as? String { return description }
      if let error = object["error"] as? String { return error }
      if let messages = object["errorMessages"] as? [String], let first = messages.first {
        return first
      }
      if let errors = object["errors"] as? [String: String], let first = errors.values.first {
        return first
      }
    }
    return String(data: data, encoding: .utf8) ?? "Unknown error"
  }
}
