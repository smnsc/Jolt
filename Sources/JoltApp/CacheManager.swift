import AppKit
import CryptoKit
import Foundation
import JoltCore

struct MetadataSnapshot: Codable, Sendable {
  let siteID: String
  let projects: [JiraProject]
  let issueTypes: [JiraIssueType]
  let fetchedAt: Date

  var isFresh: Bool {
    fetchedAt.timeIntervalSinceNow > -(24 * 60 * 60)
  }
}

actor CacheManager: CacheManaging {
  static let shared = CacheManager()

  private let fileManager = FileManager.default
  private let rootURL: URL
  private let imageDirectory: URL
  private let metadataURL: URL

  init(rootURL: URL? = nil) {
    let base =
      rootURL
      ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
      .appendingPathComponent("Jolt", isDirectory: true)
    self.rootURL = base
    self.imageDirectory = base.appendingPathComponent("IssueTypeImages", isDirectory: true)
    self.metadataURL = base.appendingPathComponent("metadata.json")
    // Builds that briefly supported Recently Opened stored issue snapshots here. Remove the
    // obsolete data when upgrading now that the feature no longer exists.
    try? FileManager.default.removeItem(at: base.appendingPathComponent("recent-issues.json"))
  }

  func metadata() -> MetadataSnapshot? {
    guard let data = try? Data(contentsOf: metadataURL) else { return nil }
    return try? JSONDecoder().decode(MetadataSnapshot.self, from: data)
  }

  func save(metadata: MetadataSnapshot) throws {
    try ensureDirectories()
    let data = try JSONEncoder().encode(metadata)
    try data.write(to: metadataURL, options: .atomic)
  }

  func imageData(for url: URL) -> Data? {
    try? Data(contentsOf: imageFileURL(for: url))
  }

  func save(imageData: Data, for url: URL) throws {
    try ensureDirectories()
    try imageData.write(to: imageFileURL(for: url), options: .atomic)
  }

  func clear() async throws {
    if fileManager.fileExists(atPath: rootURL.path) {
      try fileManager.removeItem(at: rootURL)
    }
    URLCache.shared.removeAllCachedResponses()
  }

  func diskUsage() throws -> Int64 {
    guard fileManager.fileExists(atPath: rootURL.path) else { return 0 }

    let resourceKeys: [URLResourceKey] = [
      .isRegularFileKey,
      .fileAllocatedSizeKey,
      .totalFileAllocatedSizeKey,
    ]
    guard
      let files = fileManager.enumerator(
        at: rootURL,
        includingPropertiesForKeys: resourceKeys,
        options: [.skipsHiddenFiles]
      )
    else { return 0 }

    var byteCount: Int64 = 0
    for case let fileURL as URL in files {
      let values = try fileURL.resourceValues(forKeys: Set(resourceKeys))
      guard values.isRegularFile == true else { continue }
      byteCount += Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
    }
    return byteCount
  }

  func directoryURL() throws -> URL {
    try ensureDirectories()
    return rootURL
  }

  private func ensureDirectories() throws {
    try fileManager.createDirectory(at: imageDirectory, withIntermediateDirectories: true)
  }

  private func imageFileURL(for url: URL) -> URL {
    let hash = SHA256.hash(data: Data(url.absoluteString.utf8))
    let name = hash.map { String(format: "%02x", $0) }.joined()
    return imageDirectory.appendingPathComponent(name)
  }

}

@MainActor
final class ImageRepository: ObservableObject {
  private let memory = NSCache<NSURL, NSImage>()
  private var inFlight: [NSURL: Task<NSImage?, Never>] = [:]
  private let client: JiraServing
  private let cache: CacheManager

  init(client: JiraServing, cache: CacheManager = .shared) {
    self.client = client
    self.cache = cache
  }

  func image(for url: URL) async -> NSImage? {
    let key = url as NSURL
    if let image = memory.object(forKey: key) { return image }
    if let task = inFlight[key] { return await task.value }

    let task: Task<NSImage?, Never> = Task { [client, cache] in
      let data: Data
      if let cached = await cache.imageData(for: url) {
        data = cached
      } else {
        guard let downloaded = try? await client.data(from: url) else { return nil }
        data = downloaded
        try? await cache.save(imageData: downloaded, for: url)
      }
      guard !Task.isCancelled else { return nil }
      return await Task.detached(priority: .utility) { NSImage(data: data) }.value
    }
    inFlight[key] = task
    let image = await task.value
    inFlight[key] = nil
    if let image { memory.setObject(image, forKey: key) }
    return image
  }

  func clearMemory() {
    inFlight.values.forEach { $0.cancel() }
    inFlight = [:]
    memory.removeAllObjects()
  }
}
