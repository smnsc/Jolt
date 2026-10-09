import Combine
import Foundation
import Sparkle

/// One updater for the app lifetime. Sparkle owns its settings and install lifecycle.
@MainActor
final class AppUpdater: ObservableObject {
  static let shared = AppUpdater()

  @Published private(set) var canCheckForUpdates = false
  @Published private(set) var checkFrequency: UpdateCheckFrequency = .daily
  @Published private(set) var startupError: String?

  private let controller: SPUStandardUpdaterController
  private var started = false

  private init() {
    controller = SPUStandardUpdaterController(
      startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
    controller.updater.publisher(for: \.canCheckForUpdates)
      .receive(on: DispatchQueue.main)
      .assign(to: &$canCheckForUpdates)
    if let stored = UserDefaults.standard.string(forKey: "updateCheckFrequency"),
       let frequency = UpdateCheckFrequency(rawValue: stored) {
      checkFrequency = frequency
    } else {
      checkFrequency = controller.updater.automaticallyChecksForUpdates ? .daily : .never
    }
  }

  func start() {
    guard !started else { return }
    do {
      applyFrequency()
      try controller.updater.start()
      started = true
      if checkFrequency == .onLaunch {
        controller.updater.checkForUpdatesInBackground()
      }
    } catch {
      startupError = error.localizedDescription
    }
  }

  func checkForUpdates() {
    controller.checkForUpdates(nil)
  }

  func setCheckFrequency(_ frequency: UpdateCheckFrequency) {
    checkFrequency = frequency
    UserDefaults.standard.set(frequency.rawValue, forKey: "updateCheckFrequency")
    applyFrequency()
  }

  private func applyFrequency() {
    let updater = controller.updater
    updater.automaticallyDownloadsUpdates = false
    updater.updateCheckInterval = checkFrequency == .monthly ? 30 * 24 * 60 * 60 : 24 * 60 * 60
    updater.automaticallyChecksForUpdates = checkFrequency == .daily || checkFrequency == .monthly
  }
}

enum UpdateCheckFrequency: String, CaseIterable {
  case onLaunch, daily, monthly, never

  var title: String {
    switch self {
    case .onLaunch: return "On Launch"
    case .daily: return "Daily"
    case .monthly: return "Monthly"
    case .never: return "Never"
    }
  }
}

enum JoltLinks {
  static let support = URL(string: "https://ko-fi.com/simonsc")!
  static let source = URL(string: "https://github.com/smnsc/Jolt")!
}
