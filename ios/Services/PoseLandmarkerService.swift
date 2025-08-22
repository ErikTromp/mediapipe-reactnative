import UIKit
import MediaPipeTasksVision
import AVFoundation

/**
 This protocol must be adopted by any class that wants to get the detection results of the pose landmarker in live stream mode.
 */
protocol PoseLandmarkerServiceLiveStreamDelegate: AnyObject {
    func poseLandmarkerService(_ poseLandmarkerService: PoseLandmarkerService,
                               didFinishDetection result: ResultBundle?,
                               error: Error?)
}

/**
 This protocol must be adopted by any class that wants to take appropriate actions during  different stages of pose landmark on videos.
 */
protocol PoseLandmarkerServiceVideoDelegate: AnyObject {
    func poseLandmarkerService(_ poseLandmarkerService: PoseLandmarkerService,
                               didFinishDetectionOnVideoFrame index: Int)
    func poseLandmarkerService(_ poseLandmarkerService: PoseLandmarkerService,
                               willBeginDetection totalframeCount: Int)
}


// Initializes and calls the MediaPipe APIs for detection.
class PoseLandmarkerService: NSObject {
    
    weak var liveStreamDelegate: PoseLandmarkerServiceLiveStreamDelegate?
    weak var videoDelegate: PoseLandmarkerServiceVideoDelegate?
    
    var poseLandmarker: PoseLandmarker?
    private(set) var runningMode = RunningMode.image
    private var numPoses: Int
    private var minPoseDetectionConfidence: Float
    private var minPosePresenceConfidence: Float
    private var minTrackingConfidence: Float
    private var modelPath: String
    private var delegate: PoseLandmarkerDelegate
    
    // Performance optimization properties
    private var inputResolution: Int
    private var detectionFrequency: Int // milliseconds
    private var lastDetectionTime: TimeInterval = 0
    
    // MARK: - Custom Initializer
    private init?(modelPath: String?,
                  runningMode:RunningMode,
                  numPoses: Int,
                  minPoseDetectionConfidence: Float,
                  minPosePresenceConfidence: Float,
                  minTrackingConfidence: Float,
                  delegate: PoseLandmarkerDelegate,
                  inputResolution: Int = 640,
                  detectionFrequency: Int = 10) {
        guard let modelPath = modelPath else { return nil }
        self.modelPath = modelPath
        self.runningMode = runningMode
        self.numPoses = numPoses
        self.minPoseDetectionConfidence = minPoseDetectionConfidence
        self.minPosePresenceConfidence = minPosePresenceConfidence
        self.minTrackingConfidence = minTrackingConfidence
        self.delegate = delegate
        self.inputResolution = inputResolution
        self.detectionFrequency = detectionFrequency
        super.init()
        
        createPoseLandmarker()
    }
    
    private func createPoseLandmarker() {
        let poseLandmarkerOptions = PoseLandmarkerOptions()
        poseLandmarkerOptions.runningMode = runningMode
        poseLandmarkerOptions.numPoses = numPoses
        poseLandmarkerOptions.minPoseDetectionConfidence = minPoseDetectionConfidence
        poseLandmarkerOptions.minPosePresenceConfidence = minPosePresenceConfidence
        poseLandmarkerOptions.minTrackingConfidence = minTrackingConfidence
        poseLandmarkerOptions.baseOptions.modelAssetPath = modelPath
        poseLandmarkerOptions.baseOptions.delegate = delegate.delegate
        if runningMode == .liveStream {
            poseLandmarkerOptions.poseLandmarkerLiveStreamDelegate = self
        }
        do {
            poseLandmarker = try PoseLandmarker(options: poseLandmarkerOptions)
        }
        catch {
            print(error)
        }
    }
    
    // MARK: - Static Initializers
    static func videoPoseLandmarkerService(
        modelPath: String?,
        numPoses: Int,
        minPoseDetectionConfidence: Float,
        minPosePresenceConfidence: Float,
        minTrackingConfidence: Float,
        videoDelegate: PoseLandmarkerServiceVideoDelegate?,
        delegate: PoseLandmarkerDelegate) -> PoseLandmarkerService? {
            let poseLandmarkerService = PoseLandmarkerService(
                modelPath: modelPath,
                runningMode: .video,
                numPoses: numPoses,
                minPoseDetectionConfidence: minPoseDetectionConfidence,
                minPosePresenceConfidence: minPosePresenceConfidence,
                minTrackingConfidence: minTrackingConfidence,
                delegate: delegate)
            poseLandmarkerService?.videoDelegate = videoDelegate
            return poseLandmarkerService
        }
    
    static func liveStreamPoseLandmarkerService(
        modelPath: String?,
        numPoses: Int,
        minPoseDetectionConfidence: Float,
        minPosePresenceConfidence: Float,
        minTrackingConfidence: Float,
        liveStreamDelegate: PoseLandmarkerServiceLiveStreamDelegate?,
        delegate: PoseLandmarkerDelegate,
        inputResolution: Int = 640,
        detectionFrequency: Int = 10) -> PoseLandmarkerService? {
            let poseLandmarkerService = PoseLandmarkerService(
                modelPath: modelPath,
                runningMode: .liveStream,
                numPoses: numPoses,
                minPoseDetectionConfidence: minPoseDetectionConfidence,
                minPosePresenceConfidence: minPosePresenceConfidence,
                minTrackingConfidence: minTrackingConfidence,
                delegate: delegate,
                inputResolution: inputResolution,
                detectionFrequency: detectionFrequency)
            poseLandmarkerService?.liveStreamDelegate = liveStreamDelegate
            
            return poseLandmarkerService
        }
    
    static func stillImageLandmarkerService(
        modelPath: String?,
        numPoses: Int,
        minPoseDetectionConfidence: Float,
        minPosePresenceConfidence: Float,
        minTrackingConfidence: Float,
        delegate: PoseLandmarkerDelegate) -> PoseLandmarkerService? {
            let poseLandmarkerService = PoseLandmarkerService(
                modelPath: modelPath,
                runningMode: .image,
                numPoses: numPoses,
                minPoseDetectionConfidence: minPoseDetectionConfidence,
                minPosePresenceConfidence: minPosePresenceConfidence,
                minTrackingConfidence: minTrackingConfidence,
                delegate: delegate)
            
            return poseLandmarkerService
        }
    
    // MARK: - Detection Methods for Different Modes
    /**
     This method return PoseLandmarkerResult and infrenceTime when receive an image
     **/
    func detect(image: UIImage) -> ResultBundle? {
        guard let mpImage = try? MPImage(uiImage: image) else {
            return nil
        }
        do {
            let startDate = Date()
            let result = try poseLandmarker?.detect(image: mpImage)
            let inferenceTime = Date().timeIntervalSince(startDate) * 1000
            return ResultBundle(inferenceTime: inferenceTime, poseLandmarkerResults: [result])
        } catch {
            print(error)
            return nil
        }
    }
    
    func detectAsync(
        sampleBuffer: CMSampleBuffer,
        orientation: UIImage.Orientation,
        timeStamps: Int) {
            
            // Check detection frequency - skip frames if too frequent
            let currentTime = Date().timeIntervalSince1970 * 1000
            if detectionFrequency > 0 && currentTime - lastDetectionTime < Double(detectionFrequency) {
                return
            }
            lastDetectionTime = currentTime
            
            guard let image = try? MPImage(sampleBuffer: sampleBuffer, orientation: orientation) else {
                return
            }
            
            // Resize image for better performance if needed
            let resizedImage = resizeImageIfNeeded(image)
            
            do {
                try poseLandmarker?.detectAsync(image: resizedImage, timestampInMilliseconds: timeStamps)
            } catch {
                print(error)
            }
        }
    
    private func resizeImageIfNeeded(_ image: MPImage) -> MPImage {
        // Only resize if the image is larger than target resolution
        if image.width > inputResolution || image.height > inputResolution {
            // Calculate new dimensions maintaining aspect ratio
            let aspectRatio = Double(image.width) / Double(image.height)
            let newWidth: Int
            let newHeight: Int
            
            if aspectRatio > 1.0 {
                // Landscape
                newWidth = inputResolution
                newHeight = Int(Double(inputResolution) / aspectRatio)
            } else {
                // Portrait
                newHeight = inputResolution
                newWidth = Int(Double(inputResolution) * aspectRatio)
            }
            
            // Create a new MPImage with the target size
            // Note: This is a simplified approach - in production you might want to use Core Image filters
            // for better quality and performance
            if let cgImage = image.cgImage {
                let colorSpace = CGColorSpaceCreateDeviceRGB()
                let context = CGContext(data: nil,
                                      width: newWidth,
                                      height: newHeight,
                                      bitsPerComponent: 8,
                                      bytesPerRow: newWidth * 4,
                                      space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
                
                context?.interpolationQuality = .medium
                context?.draw(cgImage, in: CGRect(x: 0, y: 0, width: newWidth, height: newHeight))
                
                if let resizedCGImage = context?.makeImage() {
                    return MPImage(cgImage: resizedCGImage)
                }
            }
        }
        return image
    }
    
    func clearPoseLandmarker() {
        poseLandmarker = nil
    }
    
    func updateModel(modelPath: String) {
        clearPoseLandmarker()
        self.modelPath = modelPath
        createPoseLandmarker()
    }
    
    func updateInputResolution(_ resolution: Int) {
        inputResolution = resolution
    }
    
    func updateDetectionFrequency(_ frequencyMs: Int) {
        detectionFrequency = frequencyMs
    }
    
    func detect(
        videoAsset: AVAsset,
        durationInMilliseconds: Double,
        inferenceIntervalInMilliseconds: Double) async -> ResultBundle? {
            let startDate = Date()
            let assetGenerator = imageGenerator(with: videoAsset)
            
            let frameCount = Int(durationInMilliseconds / inferenceIntervalInMilliseconds)
            Task { @MainActor in
                videoDelegate?.poseLandmarkerService(self, willBeginDetection: frameCount)
            }
            
            let poseLandmarkerResultTuple = detectPoseLandmarksInFramesGenerated(
                by: assetGenerator,
                totalFrameCount: frameCount,
                atIntervalsOf: inferenceIntervalInMilliseconds)
            
            return ResultBundle(
                inferenceTime: Date().timeIntervalSince(startDate) / Double(frameCount) * 1000,
                poseLandmarkerResults: poseLandmarkerResultTuple.poseLandmarkerResults,
                size: poseLandmarkerResultTuple.videoSize)
        }
    
    private func imageGenerator(with videoAsset: AVAsset) -> AVAssetImageGenerator {
        let generator = AVAssetImageGenerator(asset: videoAsset)
        generator.requestedTimeToleranceBefore = CMTimeMake(value: 1, timescale: 25)
        generator.requestedTimeToleranceAfter = CMTimeMake(value: 1, timescale: 25)
        generator.appliesPreferredTrackTransform = true
        
        return generator
    }
    
    private func detectPoseLandmarksInFramesGenerated(
        by assetGenerator: AVAssetImageGenerator,
        totalFrameCount frameCount: Int,
        atIntervalsOf inferenceIntervalMs: Double)
    -> (poseLandmarkerResults: [PoseLandmarkerResult?], videoSize: CGSize)  {
        var poseLandmarkerResults: [PoseLandmarkerResult?] = []
        var videoSize = CGSize.zero
        
        for i in 0..<frameCount {
            let timestampMs = Int(inferenceIntervalMs) * i // ms
            let image: CGImage
            do {
                let time = CMTime(value: Int64(timestampMs), timescale: 1000)
                image = try assetGenerator.copyCGImage(at: time, actualTime: nil)
            } catch {
                print(error)
                return (poseLandmarkerResults, videoSize)
            }
            
            let uiImage = UIImage(cgImage:image)
            videoSize = uiImage.size
            
            do {
                let result = try poseLandmarker?.detect(
                    videoFrame: MPImage(uiImage: uiImage),
                    timestampInMilliseconds: timestampMs)
                poseLandmarkerResults.append(result)
                Task { @MainActor in
                    videoDelegate?.poseLandmarkerService(self, didFinishDetectionOnVideoFrame: i)
                }
            } catch {
                print(error)
            }
        }
        
        return (poseLandmarkerResults, videoSize)
    }
}

// MARK: - PoseLandmarkerLiveStreamDelegate Methods
extension PoseLandmarkerService: PoseLandmarkerLiveStreamDelegate {
    func poseLandmarker(_ poseLandmarker: PoseLandmarker, didFinishDetection result: PoseLandmarkerResult?, timestampInMilliseconds: Int, error: (any Error)?) {
        let resultBundle = ResultBundle(
            inferenceTime: Date().timeIntervalSince1970 * 1000 - Double(timestampInMilliseconds),
            poseLandmarkerResults: [result])
        liveStreamDelegate?.poseLandmarkerService(
            self,
            didFinishDetection: resultBundle,
            error: error)
    }
}

/// A result from the `PoseLandmarkerService`.
struct ResultBundle {
    let inferenceTime: Double
    let poseLandmarkerResults: [PoseLandmarkerResult?]
    var size: CGSize = .zero
}
