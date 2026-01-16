package com.tsmediapipe;

import android.util.Log;

import androidx.appcompat.app.AppCompatActivity;
import androidx.camera.core.CameraSelector;

import com.facebook.react.bridge.Promise;
import com.facebook.react.bridge.ReactApplicationContext;
import com.facebook.react.bridge.ReactContextBaseJavaModule;
import com.facebook.react.bridge.ReactMethod;
import com.facebook.react.bridge.WritableMap;
import com.facebook.react.bridge.Arguments;

public class MediaPipeNativeModule extends ReactContextBaseJavaModule {

  public MediaPipeNativeModule(ReactApplicationContext reactContext) {
    super(reactContext);

    ReactContextProvider.reactApplicationContext = reactContext;
  }

  @Override
  public String getName() {
    return "MediaPipeNativeModule";
  }

  @ReactMethod
  public void switchCameraMethod() {
    Log.d("switchCameraMethod", "Create event called with name: ");
    AppCompatActivity activity = (AppCompatActivity) getCurrentActivity();

    if (activity != null && CameraFragmentManager.INSTANCE.getCameraFragment() != null) {
      activity.runOnUiThread(new Runnable() {
        @Override
        public void run() {
          CameraFragmentManager.INSTANCE.getCameraFragment().switchCamera();
        }
      });
    } else {
      Log.e("switchCameraMethod", "CameraFragment is not initialized");
    }
  }

  /**
   * Get the current camera facing direction and mirroring status.
   * Returns an object with:
   * - isFrontCamera: boolean - true if front camera is active
   * - isMirrored: boolean - always false (frames and landmarks are NEVER mirrored)
   * 
   * Note: On Android, base64 images and MediaPipe landmarks are NEVER mirrored,
   * regardless of camera position. Only rotation is applied to match display orientation.
   */
  @ReactMethod
  public void getCameraInfo(Promise promise) {
    try {
      AppCompatActivity activity = (AppCompatActivity) getCurrentActivity();
      if (activity == null || CameraFragmentManager.INSTANCE.getCameraFragment() == null) {
        promise.reject("CAMERA_NOT_READY", "Camera is not initialized");
        return;
      }

      activity.runOnUiThread(new Runnable() {
        @Override
        public void run() {
          try {
            int cameraFacing = CameraFragmentManager.INSTANCE.getCameraFragment().getCameraFacing();
            boolean isFrontCamera = cameraFacing == CameraSelector.LENS_FACING_FRONT;
            
            WritableMap result = Arguments.createMap();
            result.putBoolean("isFrontCamera", isFrontCamera);
            // On Android, frames sent to MediaPipe are NEVER mirrored
            // Base64 images and landmarks are always non-mirrored regardless of camera position
            result.putBoolean("isMirrored", false);
            
            promise.resolve(result);
          } catch (Exception e) {
            Log.e("getCameraInfo", "Error getting camera info: " + e.getMessage(), e);
            promise.reject("ERROR", "Failed to get camera info: " + e.getMessage());
          }
        }
      });
    } catch (Exception e) {
      Log.e("getCameraInfo", "Error: " + e.getMessage(), e);
      promise.reject("ERROR", "Failed to get camera info: " + e.getMessage());
    }
  }
}
