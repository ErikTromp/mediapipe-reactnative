import Foundation
import AVFoundation
import UIKit
import React
import MediaPipeTasksVision

@objc(MediapipeVideoModule)
class MediapipeVideoModule: NSObject, RCTBridgeModule {

  private var isProcessing: Bool = false
  private var cancelRequested: Bool = false
  private var startTimestampMs: Int = 0

  static func moduleName() -> String! { return "MediapipeVideoModule" }
  static func requiresMainQueueSetup() -> Bool { false }

  @objc
  func cancelProcessVideo() {
    cancelRequested = true
  }

  @objc
  func processVideo(_ uri: String,
                    options: NSDictionary,
                    onLandmark: @escaping RCTResponseSenderBlock,
                    onComplete: @escaping RCTResponseSenderBlock) {
    guard !isProcessing else { return }
    isProcessing = true
    cancelRequested = false

    let fps = (options["fps"] as? NSNumber)?.doubleValue ?? 15.0
    let includeBase64 = (options["includeBase64"] as? NSNumber)?.boolValue ?? true
    let jpegQuality = (options["jpegQuality"] as? NSNumber)?.doubleValue ?? 70.0
    let mirror = (options["mirror"] as? NSNumber)?.boolValue ?? false
    let maxFrames = (options["maxFrames"] as? NSNumber)?.intValue

    startTimestampMs = Int(Date().timeIntervalSince1970 * 1000)

    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      guard let self = self else { return }
      defer { self.isProcessing = false }

      NSLog("[MediapipeVideoModule] processVideo start uri=%@ options=%@", uri, options)

      // Support file:// and content:// via security-scoped URLs if needed
      let url: URL
      if let parsed = URL(string: uri) {
        url = parsed
      } else {
        NSLog("[MediapipeVideoModule] invalid URI")
        onComplete([["framesProcessed": 0, "durationMs": 0, "error": "invalid_uri"]])
        return
      }

      let asset = AVAsset(url: url)
      let durationSeconds = CMTimeGetSeconds(asset.duration)
      let durationMs = Int(durationSeconds * 1000.0)
      let stepMs = max(1, Int(1000.0 / fps))
      NSLog("[MediapipeVideoModule] durationMs=%d stepMs=%d", durationMs, stepMs)

      // Landmarker setup (video mode)
      // Resolve model path from pod resource or bundle
      let modelPath = Bundle.main.path(forResource: "pose_landmarker_full", ofType: "task")
        ?? Bundle(for: type(of: self)).path(forResource: "pose_landmarker_full", ofType: "task")
      guard let service = PoseLandmarkerService.videoPoseLandmarkerService(
        modelPath: modelPath,
        numPoses: 1,
        minPoseDetectionConfidence: 0.5,
        minPosePresenceConfidence: 0.5,
        minTrackingConfidence: 0.5,
        videoDelegate: nil,
        delegate: .CPU) else {
        NSLog("[MediapipeVideoModule] failed to initialize PoseLandmarkerService")
        onComplete([["framesProcessed": 0, "durationMs": 0, "error": "landmarker_init_failed"]])
        return
      }

      let generator = AVAssetImageGenerator(asset: asset)
      generator.requestedTimeToleranceBefore = CMTimeMake(value: 1, timescale: 25)
      generator.requestedTimeToleranceAfter = CMTimeMake(value: 1, timescale: 25)
      generator.appliesPreferredTrackTransform = true

      var framesProcessed = 0
      var currentMs = 0
      var frameNumber = 0

      while currentMs <= durationMs {
        if self.cancelRequested { break }
        if let maxFrames = maxFrames, frameNumber >= maxFrames { break }

        let time = CMTime(value: Int64(currentMs), timescale: 1000)
        guard let cgImage = try? generator.copyCGImage(at: time, actualTime: nil) else {
          if frameNumber < 3 { NSLog("[MediapipeVideoModule] copyCGImage failed at ms=%d", currentMs) }
          currentMs += stepMs
          frameNumber += 1
          continue
        }

        var uiImage = UIImage(cgImage: cgImage)
        if mirror {
          uiImage = UIImage(cgImage: cgImage, scale: uiImage.scale, orientation: .upMirrored)
        }

        // Inference
        let timestampMs = currentMs
        let result: PoseLandmarkerResult?
        do {
          result = try service.poseLandmarker?.detect(
            videoFrame: MPImage(uiImage: uiImage),
            timestampInMilliseconds: timestampMs)
        } catch {
          NSLog("[MediapipeVideoModule] detect error at ms=%d error=%@", timestampMs, String(describing: error))
          result = nil
        }

        // Build payload matching live onLandmark
        var swiftDict: [String: Any] = [:]
        if let res = result {
          let landmarks = res.landmarks.first
          let worldLandmarks = res.worldLandmarks.first

          var landmarksArray: [[String: Any]] = []
          if let landmarks = landmarks {
            for lm in landmarks {
              landmarksArray.append([
                "x": lm.x,
                "y": lm.y,
                "z": lm.z,
                "visibility": lm.visibility?.floatValue as Any,
                "presence": lm.presence?.floatValue as Any,
              ])
            }
          }

          var worldLandmarksArray: [[String: Any]] = []
          if let wls = worldLandmarks {
            for lm in wls {
              worldLandmarksArray.append([
                "x": lm.x,
                "y": lm.y,
                "z": lm.z,
                "visibility": lm.visibility?.floatValue as Any,
                "presence": lm.presence?.floatValue as Any,
              ])
            }
          }

          let size = uiImage.size
          swiftDict["landmarks"] = landmarksArray
          swiftDict["worldLandmarks"] = worldLandmarksArray
          swiftDict["additionalData"] = [
            "height": size.height,
            "width": size.width,
            "presentationTimeStamp": Double(timestampMs),
            "frameNumber": frameNumber,
            "startTimestamp": self.startTimestampMs,
          ]

          if includeBase64, let jpeg = uiImage.jpegData(compressionQuality: CGFloat(jpegQuality / 100.0)) {
            let b64 = jpeg.base64EncodedString()
            swiftDict["frameBase64"] = b64
          }
        }

        onLandmark([swiftDict])

        framesProcessed += 1
        frameNumber += 1
        currentMs += stepMs
      }

      onComplete([["framesProcessed": framesProcessed, "durationMs": durationMs]])
    }
  }
}


