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
  private let client: JiraServing
  private let cache: CacheManager

  init(client: JiraServing, cache: CacheManager = .shared) {
    self.client = client
    self.cache = cache
  }

  func image(for url: URL) async -> NSImage? {
    if let image = memory.object(forKey: url as NSURL) { return image }
    if let data = await cache.imageData(for: url), let image = NSImage(data: data) {
      memory.setObject(image, forKey: url as NSURL)
      return image
    }
    guard let data = try? await client.data(from: url), let image = NSImage(data: data) else {
      return nil
    }
    memory.setObject(image, forKey: url as NSURL)
    try? await cache.save(imageData: data, for: url)
    return image
  }

  func clearMemory() {
    memory.removeAllObjects()
  }
}
