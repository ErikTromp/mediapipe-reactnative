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
}
