import Foundation
import SwiftUI

enum AtlassianURLs {
  static let oauthDocumentation = URL(
    string: "https://developer.atlassian.com/cloud/jira/platform/oauth-2-3lo-apps/")!
  static let apiTokens = URL(
    string: "https://id.atlassian.com/manage-profile/security/api-tokens")!
}

struct JiraConnectionView: View {
  private enum Field: Hashable {
    case site
    case email
    case apiKey
  }

  @EnvironmentObject private var model: AppModel
  @State private var siteURL = ""
  @State private var email = ""
  @State private var apiKey = ""
  @FocusState private var focusedField: Field?

  var body: some View {
    ScrollView {
      VStack(spacing: 14) {
        Image(systemName: "key.fill")
          .font(.system(size: 38))
          .foregroundStyle(.blue)
        Text("Connect Jira with an API key")
          .font(.title2.bold())

        VStack(alignment: .leading, spacing: 7) {
          Text("1. Open Atlassian API token settings and create an API token.")
          Text("2. Copy the token, then paste it below with your Jira site and Atlassian email.")
          Link(destination: AtlassianURLs.apiTokens) {
            Label("Open Atlassian API token settings", systemImage: "arrow.up.right.square")
          }
        }
        .font(.callout)
        .frame(maxWidth: 500, alignment: .leading)

        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
          GridRow {
            Text("Jira site")
            TextField("your-team.atlassian.net", text: $siteURL)
              .textFieldStyle(.roundedBorder)
              .focused($focusedField, equals: .site)
          }
          GridRow {
            Text("Email")
            TextField("name@company.com", text: $email)
              .textFieldStyle(.roundedBorder)
              .focused($focusedField, equals: .email)
          }
          GridRow {
            Text("API key")
            SecureField("Paste your Atlassian API token", text: $apiKey)
              .textFieldStyle(.roundedBorder)
              .focused($focusedField, equals: .apiKey)
              .onSubmit(connect)
          }
        }
        .frame(maxWidth: 500)

        HStack(spacing: 10) {
          if model.isConnecting {
            ProgressView().controlSize(.small)
            Button("Cancel") { model.cancelConnection() }
          } else {
            Button("Connect Jira", action: connect)
              .buttonStyle(.borderedProminent)
              .disabled(!canConnect)
          }
        }
        .controlSize(.large)

        JiraAPIKeyExplanation()

        Text("Your API key is stored securely in macOS Keychain.")
          .font(.caption)
          .foregroundStyle(.secondary)

        if let error = model.errorMessage {
          Text(error)
            .font(.callout)
            .foregroundStyle(.red)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 520)
        }
      }
      .frame(maxWidth: .infinity)
    }
    .onAppear { focusSiteField() }
    .onReceive(NotificationCenter.default.publisher(for: .focusSearchField)) { _ in
      focusSiteField()
    }
  }

  private var canConnect: Bool {
    !siteURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  private func connect() {
    guard canConnect, !model.isConnecting else { return }
    model.connect(siteURL: siteURL, email: email, apiKey: apiKey)
  }

  private func focusSiteField() {
    DispatchQueue.main.async {
      focusedField = .site
    }
  }
}

/// Shared connection help for onboarding and account settings.
struct JiraAPIKeyExplanation: View {
  @State private var isPresented = false

  var body: some View {
    Button("Why an API key?") { isPresented = true }
      .buttonStyle(.link)
      .popover(isPresented: $isPresented) {
        VStack(alignment: .leading, spacing: 12) {
          Text("Why an API key?")
            .font(.headline)
          Text("An API key (Atlassian calls it an API token) lets Jolt connect directly to Jira on your behalf.")
          Text("Atlassian’s documented Jira browser sign-in flow, OAuth 2.0 (3LO), requires an app client secret. A distributed Mac app cannot keep that shared secret private. Using this flow safely would require a hosted authentication service, which Jolt does not have.")
          Text("Your token is stored in macOS Keychain and sent only to Atlassian. Jolt only reads Jira data. You can revoke the token at any time in your Atlassian account.")
          Link("Atlassian’s Jira OAuth documentation", destination: AtlassianURLs.oauthDocumentation)
        }
        .font(.callout)
        .fixedSize(horizontal: false, vertical: true)
        .padding(20)
        .frame(width: 380)
      }
  }
}
