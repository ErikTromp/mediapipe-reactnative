import Foundation
import React

@objc(TsMediapipeViewManager)
class TsMediapipeViewManager: RCTViewManager {
    
    // Use weak reference to avoid retaining views that are being deallocated
    private weak var currentCameraView: CameraView?
    
    override func view() -> (UIView) {
        let view = CameraView()
        currentCameraView = view
        return view
    }
    
    @objc override static func requiresMainQueueSetup() -> Bool {
        return true
    }
    
    @objc func switchCamera() {
        // Ensure we're on main thread and check if view is still valid
        DispatchQueue.main.async { [weak self] in
            guard let view = self?.currentCameraView else {
                return
            }
            view.switchCamera()
        }
    }
    
    @objc func getCameraInfo(_ resolve: @escaping RCTPromiseResolveBlock, rejecter reject: @escaping RCTPromiseRejectBlock) {
        DispatchQueue.main.async { [weak self] in
            guard let view = self?.currentCameraView else {
                reject("CAMERA_NOT_READY", "Camera view is not initialized", nil)
                return
            }
            let info = view.getCameraInfo()
            resolve(info)
        }
    }
}
