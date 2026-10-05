import Combine
import Foundation
import Sparkle

/// One updater for the app lifetime. Sparkle owns its settings and install lifecycle.
@MainActor
final class AppUpdater: ObservableObject {
  static let shared = AppUpdater()

  @Published private(set) var canCheckForUpdates = false
  @Published private(set) var automaticallyChecksForUpdates = false
  @Published private(set) var automaticallyDownloadsUpdates = false
  @Published private(set) var startupError: String?

  private let controller: SPUStandardUpdaterController
  private var started = false

  private init() {
    controller = SPUStandardUpdaterController(
      startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
    controller.updater.publisher(for: \.canCheckForUpdates)
      .receive(on: DispatchQueue.main)
      .assign(to: &$canCheckForUpdates)
    controller.updater.publisher(for: \.automaticallyChecksForUpdates)
      .receive(on: DispatchQueue.main)
      .assign(to: &$automaticallyChecksForUpdates)
    controller.updater.publisher(for: \.automaticallyDownloadsUpdates)
      .receive(on: DispatchQueue.main)
      .assign(to: &$automaticallyDownloadsUpdates)
  }

  func start() {
    guard !started else { return }
    do {
      try controller.updater.start()
      started = true
    } catch {
      startupError = error.localizedDescription
    }
  }

  func checkForUpdates() {
    controller.checkForUpdates(nil)
  }

  func setAutomaticChecks(_ enabled: Bool) {
    controller.updater.automaticallyChecksForUpdates = enabled
  }

  func setAutomaticDownloads(_ enabled: Bool) {
    controller.updater.automaticallyDownloadsUpdates = enabled
  }
}

enum JoltLinks {
  static let support = URL(string: "https://ko-fi.com/simonsc")!
  static let source = URL(string: "https://github.com/smnsc/Jolt")!
}
