import AVFoundation
import Flutter
import UIKit

/// Compresses photos and videos, and uploads material files with a background
/// URLSession so the bytes continue after the app is suspended or killed.
final class MaterialsUpload: NSObject, FlutterPlugin, URLSessionDelegate, URLSessionTaskDelegate, URLSessionDataDelegate {
  static let sessionIdentifier = "in.thelittlegraduates.app.materials.uploads"
  static let channelName = "in.thelittlegraduates.app/materials_upload"
  static let shared = MaterialsUpload()
  static var backgroundCompletion: (() -> Void)?

  private let lock = NSLock()
  private var session: URLSession?
  private var responseData: [Int: Data] = [:]

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: registrar.messenger())
    shared.ensureSession()
    registrar.addMethodCallDelegate(shared, channel: channel)
  }

  func ensureSession() {
    if session != nil { return }
    let config = URLSessionConfiguration.background(withIdentifier: Self.sessionIdentifier)
    config.isDiscretionary = false
    config.sessionSendsLaunchEvents = true
    session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any]
    switch call.method {
    case "videoInfo":
      videoInfo(path: args?["path"] as? String, result: result)
    case "transcodeVideo":
      transcode(source: args?["source"] as? String, dest: args?["dest"] as? String, result: result)
    case "compressImage":
      compressImage(
        source: args?["source"] as? String,
        dest: args?["dest"] as? String,
        maxEdge: CGFloat(args?["maxEdge"] as? Int ?? 1600),
        quality: CGFloat(args?["quality"] as? Int ?? 75) / 100,
        result: result
      )
    case "enqueueUpload":
      enqueue(args: args ?? [:], result: result)
    case "takeUploadResults":
      result(takeResults())
    case "inFlightUploads":
      inFlight(result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func videoInfo(path: String?, result: @escaping FlutterResult) {
    guard let path, !path.isEmpty else {
      result(FlutterError(code: "video", message: "Missing video.", details: nil))
      return
    }
    DispatchQueue.global(qos: .utility).async {
      let asset = AVURLAsset(url: URL(fileURLWithPath: path))
      guard let track = asset.tracks(withMediaType: .video).first else {
        DispatchQueue.main.async { result(nil) }
        return
      }
      let size = track.naturalSize.applying(track.preferredTransform)
      DispatchQueue.main.async {
        result(["width": Int(abs(size.width)), "height": Int(abs(size.height))])
      }
    }
  }

  private func transcode(source: String?, dest: String?, result: @escaping FlutterResult) {
    guard let source, let dest, !source.isEmpty, !dest.isEmpty else {
      result(FlutterError(code: "transcode", message: "Missing video.", details: nil))
      return
    }
    let asset = AVURLAsset(url: URL(fileURLWithPath: source))
    let presets = AVAssetExportSession.exportPresets(compatibleWith: asset)
    let preset = presets.contains(AVAssetExportPreset1280x720) ? AVAssetExportPreset1280x720 : AVAssetExportPresetMediumQuality
    guard let export = AVAssetExportSession(asset: asset, presetName: preset) else {
      result(FlutterError(code: "transcode", message: "This video cannot be compressed.", details: nil))
      return
    }
    let output = URL(fileURLWithPath: dest)
    try? FileManager.default.removeItem(at: output)
    export.outputURL = output
    export.outputFileType = .mp4
    export.shouldOptimizeForNetworkUse = true
    export.exportAsynchronously {
      DispatchQueue.main.async {
        if export.status == .completed {
          result(nil)
        } else {
          result(FlutterError(code: "transcode", message: export.error?.localizedDescription ?? "Could not compress the video.", details: nil))
        }
      }
    }
  }

  private func compressImage(source: String?, dest: String?, maxEdge: CGFloat, quality: CGFloat, result: @escaping FlutterResult) {
    guard let source, let dest, let image = UIImage(contentsOfFile: source) else {
      result(FlutterError(code: "compress", message: "Could not read the photo.", details: nil))
      return
    }
    DispatchQueue.global(qos: .utility).async {
      let longEdge = max(image.size.width, image.size.height)
      let target: UIImage
      if longEdge > maxEdge && longEdge > 0 {
        let scale = maxEdge / longEdge
        let size = CGSize(width: max(1, image.size.width * scale), height: max(1, image.size.height * scale))
        let renderer = UIGraphicsImageRenderer(size: size)
        target = renderer.image { _ in
          image.draw(in: CGRect(origin: .zero, size: size))
        }
      } else {
        let renderer = UIGraphicsImageRenderer(size: image.size)
        target = renderer.image { _ in
          image.draw(in: CGRect(origin: .zero, size: image.size))
        }
      }
      guard let data = target.jpegData(compressionQuality: min(max(quality, 0.7), 0.8)) else {
        DispatchQueue.main.async {
          result(FlutterError(code: "compress", message: "Could not write the photo.", details: nil))
        }
        return
      }
      do {
        try data.write(to: URL(fileURLWithPath: dest), options: .atomic)
        DispatchQueue.main.async { result(nil) }
      } catch {
        DispatchQueue.main.async {
          result(FlutterError(code: "compress", message: error.localizedDescription, details: nil))
        }
      }
    }
  }

  private func enqueue(args: [String: Any], result: @escaping FlutterResult) {
    ensureSession()
    guard let session else {
      result(FlutterError(code: "upload", message: "Upload session is not ready.", details: nil))
      return
    }
    let clientKey = args["clientKey"] as? String ?? ""
    let urlString = args["url"] as? String ?? ""
    let filePath = args["filePath"] as? String ?? ""
    guard let url = URL(string: urlString), !clientKey.isEmpty, FileManager.default.fileExists(atPath: filePath) else {
      store(result: ["clientKey": clientKey, "status": 0, "body": "", "error": "The photo is missing on this phone."])
      result(nil)
      return
    }
    session.getAllTasks { tasks in
      if tasks.contains(where: { $0.taskDescription == clientKey }) {
        DispatchQueue.main.async { result(nil) }
        return
      }
      do {
        let body = self.supportDir().appendingPathComponent("\(clientKey).multipart")
        try self.writeMultipart(args: args, filePath: filePath, dest: body)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        let headers = args["headers"] as? [String: String] ?? [:]
        for (name, value) in headers where name.lowercased() != "content-type" {
          request.setValue(value, forHTTPHeaderField: name)
        }
        let boundary = "lgmaterials\(clientKey.replacingOccurrences(of: "-", with: ""))"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        let task = session.uploadTask(with: request, fromFile: body)
        task.taskDescription = clientKey
        task.resume()
        DispatchQueue.main.async { result(nil) }
      } catch {
        self.store(result: ["clientKey": clientKey, "status": 0, "body": "", "error": error.localizedDescription])
        DispatchQueue.main.async { result(nil) }
      }
    }
  }

  private func writeMultipart(args: [String: Any], filePath: String, dest: URL) throws {
    let clientKey = args["clientKey"] as? String ?? "upload"
    let boundary = "lgmaterials\(clientKey.replacingOccurrences(of: "-", with: ""))"
    let fields = args["fields"] as? [String: String] ?? [:]
    let filename = (args["filename"] as? String ?? "upload.bin").replacingOccurrences(of: "\"", with: "")
    let mime = args["mime"] as? String ?? "application/octet-stream"
    let crlf = "\r\n"
    FileManager.default.createFile(atPath: dest.path, contents: nil)
    let handle = try FileHandle(forWritingTo: dest)
    func write(_ text: String) {
      handle.write(Data(text.utf8))
    }
    for (name, value) in fields {
      write("--\(boundary)\(crlf)")
      write("Content-Disposition: form-data; name=\"\(name)\"\(crlf)\(crlf)")
      write(value)
      write(crlf)
    }
    write("--\(boundary)\(crlf)")
    write("Content-Disposition: form-data; name=\"media\"; filename=\"\(filename)\"\(crlf)")
    write("Content-Type: \(mime)\(crlf)\(crlf)")
    let input = try FileHandle(forReadingFrom: URL(fileURLWithPath: filePath))
    while true {
      let chunk = input.readData(ofLength: 256 * 1024)
      if chunk.isEmpty { break }
      handle.write(chunk)
    }
    try input.close()
    write("\(crlf)--\(boundary)--\(crlf)")
    try handle.close()
  }

  private func inFlight(result: @escaping FlutterResult) {
    ensureSession()
    session?.getAllTasks { tasks in
      let keys = tasks.compactMap { $0.taskDescription }
      DispatchQueue.main.async { result(keys) }
    } ?? result([])
  }

  private func takeResults() -> [[String: Any]] {
    lock.lock()
    defer { lock.unlock() }
    let file = resultsFile()
    guard let data = try? Data(contentsOf: file),
          let decoded = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
      return []
    }
    try? FileManager.default.removeItem(at: file)
    return decoded
  }

  func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
    lock.lock()
    var existing = responseData[dataTask.taskIdentifier] ?? Data()
    existing.append(data)
    responseData[dataTask.taskIdentifier] = existing
    lock.unlock()
  }

  func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
    lock.lock()
    let data = responseData.removeValue(forKey: task.taskIdentifier) ?? Data()
    lock.unlock()
    let status = (task.response as? HTTPURLResponse)?.statusCode ?? 0
    let body = String(data: data, encoding: .utf8) ?? ""
    store(result: [
      "clientKey": task.taskDescription ?? "",
      "status": status,
      "body": body,
      "error": error?.localizedDescription as Any,
    ])
    if let key = task.taskDescription {
      try? FileManager.default.removeItem(at: supportDir().appendingPathComponent("\(key).multipart"))
    }
  }

  func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
    DispatchQueue.main.async {
      MaterialsUpload.backgroundCompletion?()
      MaterialsUpload.backgroundCompletion = nil
    }
  }

  private func store(result payload: [String: Any]) {
    lock.lock()
    defer { lock.unlock() }
    let file = resultsFile()
    var rows = (try? Data(contentsOf: file)).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [[String: Any]] } ?? []
    rows.append(payload)
    if let data = try? JSONSerialization.data(withJSONObject: rows) {
      try? data.write(to: file, options: .atomic)
    }
  }

  private func supportDir() -> URL {
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    let dir = base.appendingPathComponent("materials_uploads", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
  }

  private func resultsFile() -> URL {
    supportDir().appendingPathComponent("results.json")
  }
}
