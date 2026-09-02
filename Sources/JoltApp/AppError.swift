import Foundation

enum AppError: LocalizedError {
  case invalidJiraSiteURL
  case invalidEmail
  case missingAPIKey
  case invalidAPICredentials
  case notAuthenticated
  case noJiraSites
  case invalidResponse
  case server(status: Int, message: String)
  case shortcutUnavailable(String)

  var errorDescription: String? {
    switch self {
    case .invalidJiraSiteURL:
      return "Enter your Jira Cloud site, such as your-team.atlassian.net."
    case .invalidEmail:
      return "Enter the email address for your Atlassian account."
    case .missingAPIKey:
      return "Paste an Atlassian API key to connect."
    case .invalidAPICredentials:
      return "Jira could not verify these details. Check the site, email, API key, and Jira read permissions."
    case .notAuthenticated:
      return "Connect your Jira account to continue."
    case .noJiraSites:
      return "This Atlassian account does not have an accessible Jira Cloud site."
    case .invalidResponse:
      return "Jira returned an unexpected response."
    case .server(let status, let message):
      return "Jira request failed (\(status)): \(message)"
    case .shortcutUnavailable(let shortcut):
      return "The shortcut \(shortcut) is already in use by another app."
    }
  }
}

extension Error {
  var userFacingMessage: String {
    (self as? LocalizedError)?.errorDescription ?? localizedDescription
  }
}
