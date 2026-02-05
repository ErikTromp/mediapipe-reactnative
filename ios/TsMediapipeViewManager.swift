import Foundation
import React

@objc(TsMediapipeViewManager)
class TsMediapipeViewManager: RCTViewManager {
    
    // Strong reference to the camera view - React Native also holds a reference
    // so this won't cause a retain cycle, but ensures switchCamera works reliably
    private var cameraView: CameraView?
    
    override func view() -> (UIView) {
        let view = CameraView()
        cameraView = view
        return view
    }
    
    @objc override static func requiresMainQueueSetup() -> Bool {
        return true
    }
    
    @objc func switchCamera() {
        cameraView?.switchCamera()
    }
    
    @objc func getCameraInfo(_ resolve: @escaping RCTPromiseResolveBlock, rejecter reject: @escaping RCTPromiseRejectBlock) {
        guard let view = cameraView else {
            reject("CAMERA_NOT_READY", "Camera view is not initialized", nil)
            return
        }
        let info = view.getCameraInfo()
        resolve(info)
    }
}
