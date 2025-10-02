package com.tsmediapipe;

import android.util.Log;
import android.graphics.Bitmap;
import android.media.MediaMetadataRetriever;
import android.util.Base64;
import android.net.Uri;

import androidx.appcompat.app.AppCompatActivity;

import com.facebook.react.bridge.ReactApplicationContext;
import com.facebook.react.bridge.ReactContextBaseJavaModule;
import com.facebook.react.bridge.ReactMethod;
import com.facebook.react.bridge.Callback;
import com.facebook.react.bridge.ReadableMap;
import com.facebook.react.bridge.WritableArray;
import com.facebook.react.bridge.WritableMap;
import com.facebook.react.bridge.Arguments;

public class MediaPipeNativeModule extends ReactContextBaseJavaModule {

  private volatile boolean cancelRequested = false;

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

  @ReactMethod
  public void cancelProcessVideo() {
    cancelRequested = true;
  }

  @ReactMethod
  public void processVideo(String uri, ReadableMap options, Callback onLandmark, Callback onComplete) {
    processVideoInternal(uri, options, onLandmark, onComplete, null);
  }

  @ReactMethod
  public void processVideoWithDebug(String uri, ReadableMap options, Callback onLandmark, Callback onComplete, Callback onDebug) {
    processVideoInternal(uri, options, onLandmark, onComplete, onDebug);
  }

  private void debugLog(Callback cb, String msg) {
    Log.d("MediaPipeNativeModule", msg);
    if (cb != null) {
      try { cb.invoke(msg); } catch (Throwable ignore) {}
    }
  }

  private void processVideoInternal(String uri, ReadableMap options, Callback onLandmark, Callback onComplete, Callback onDebug) {
    cancelRequested = false;
    final double fps = options.hasKey("fps") ? options.getDouble("fps") : 15.0;
    final boolean includeBase64 = options.hasKey("includeBase64") && options.getBoolean("includeBase64");
    final int jpegQuality = options.hasKey("jpegQuality") ? options.getInt("jpegQuality") : 70;
    final boolean mirror = options.hasKey("mirror") && options.getBoolean("mirror");
    final int maxFrames = options.hasKey("maxFrames") ? options.getInt("maxFrames") : Integer.MAX_VALUE;

    new Thread(() -> {
      int framesProcessed = 0;
      try {
        debugLog(onDebug, "processVideo start uri=" + uri + ", fps=" + fps + ", includeBase64=" + includeBase64);
        MediaMetadataRetriever retriever = new MediaMetadataRetriever();
        try {
          Uri parsed = Uri.parse(uri);
          String scheme = parsed.getScheme();
          debugLog(onDebug, "setDataSource scheme=" + scheme);
          if ("content".equals(scheme) || "file".equals(scheme)) {
            android.os.ParcelFileDescriptor pfd = null;
            try {
              pfd = getReactApplicationContext().getContentResolver().openFileDescriptor(parsed, "r");
              if (pfd != null) {
                retriever.setDataSource(pfd.getFileDescriptor());
                debugLog(onDebug, "setDataSource via FileDescriptor OK");
              } else {
                retriever.setDataSource(getReactApplicationContext(), parsed);
                debugLog(onDebug, "setDataSource via Context+Uri OK (null FD)");
              }
            } finally {
              if (pfd != null) try { pfd.close(); } catch (Throwable ignore) {}
            }
          } else {
            retriever.setDataSource(uri);
            debugLog(onDebug, "setDataSource via String OK");
          }
        } catch (Throwable t) {
          debugLog(onDebug, "setDataSource failed: " + t);
          throw t;
        }
        String durationStr = null;
        try {
          durationStr = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION);
        } catch (Throwable t) {
          debugLog(onDebug, "extractMetadata(DURATION) failed: " + t);
        }
        int durationMs = durationStr != null ? Integer.parseInt(durationStr) : 0;
        int stepMs = Math.max(1, (int)Math.round(1000.0 / fps));
        int totalFrames = durationMs > 0 ? (durationMs / stepMs) + 1 : 1;
        debugLog(onDebug, "durationMs=" + durationMs + ", stepMs=" + stepMs + ", estFrames=" + totalFrames);

        // Setup PoseLandmarker in VIDEO mode
        PoseLandmarkerHelper helper = new PoseLandmarkerHelper(
          PoseLandmarkerHelper.DEFAULT_POSE_DETECTION_CONFIDENCE,
          PoseLandmarkerHelper.DEFAULT_POSE_TRACKING_CONFIDENCE,
          PoseLandmarkerHelper.DEFAULT_POSE_PRESENCE_CONFIDENCE,
          PoseLandmarkerHelper.MODEL_POSE_LANDMARKER_FULL,
          PoseLandmarkerHelper.DELEGATE_CPU,
          com.google.mediapipe.tasks.vision.core.RunningMode.VIDEO,
          getReactApplicationContext(),
          null
        );
        if (helper.isClose()) {
          debugLog(onDebug, "PoseLandmarkerHelper failed to initialize");
        } else {
          debugLog(onDebug, "PoseLandmarkerHelper initialized in VIDEO mode");
        }

        long startTs = System.currentTimeMillis();
        int frameNumber = 0;
        int lastLog = -1;
        boolean useClosestSync = false;
        int consecutiveNulls = 0;
        for (int currentMs = 0; currentMs <= durationMs; currentMs += stepMs) {
          if (cancelRequested || frameNumber >= maxFrames) break;

          debugLog(onDebug, "decoding frame#" + frameNumber + " at " + currentMs + "ms");
          Bitmap frame = null;
          try {
            frame = retriever.getFrameAtTime(
              currentMs * 1000L,
              useClosestSync ? MediaMetadataRetriever.OPTION_CLOSEST_SYNC : MediaMetadataRetriever.OPTION_CLOSEST
            );
          } catch (Throwable t) {
            debugLog(onDebug, "getFrameAtTime failed at " + currentMs + "ms: " + t);
          }
          if (frame == null) {
            consecutiveNulls++;
            if (consecutiveNulls == 3 && !useClosestSync) {
              useClosestSync = true;
              debugLog(onDebug, "switching to OPTION_CLOSEST_SYNC due to null frames");
            }
            frameNumber++;
            continue;
          } else {
            consecutiveNulls = 0;
          }
          debugLog(onDebug, "decoded bitmap w=" + frame.getWidth() + " h=" + frame.getHeight());

          // Orientation/mirror handled approximately here if needed
          Bitmap processed = frame;
          if (mirror) {
            android.graphics.Matrix mx = new android.graphics.Matrix();
            mx.preScale(-1.0f, 1.0f);
            processed = Bitmap.createBitmap(frame, 0, 0, frame.getWidth(), frame.getHeight(), mx, true);
          }

          // Build MPImage and run detectForVideo
          com.google.mediapipe.framework.image.MPImage mpImage =
              new com.google.mediapipe.framework.image.BitmapImageBuilder(processed).build();

          com.google.mediapipe.tasks.vision.poselandmarker.PoseLandmarkerResult result = null;
          try {
            result = helper.detectForVideoFrame(processed, currentMs);
          } catch (Throwable t) {
            debugLog(onDebug, "detectForVideoFrame error at " + currentMs + "ms: " + t);
          }

          WritableMap payload = Arguments.createMap();
          if (result != null) {
            int lmCount = result.landmarks().isEmpty() ? 0 : result.landmarks().get(0).size();
            debugLog(onDebug, "landmarks detected=" + lmCount);
            // landmarks
            WritableArray landmarksWritable = Arguments.createArray();
            if (!result.landmarks().isEmpty()) {
              for (com.google.mediapipe.tasks.components.containers.NormalizedLandmark lm : result.landmarks().get(0)) {
                WritableMap m = Arguments.createMap();
                m.putDouble("x", lm.x());
                m.putDouble("y", lm.y());
                m.putDouble("z", lm.z());
                if (lm.visibility().isPresent()) m.putDouble("visibility", lm.visibility().get());
                if (lm.presence().isPresent()) m.putDouble("presence", lm.presence().get());
                landmarksWritable.pushMap(m);
              }
            }
            payload.putArray("landmarks", landmarksWritable);

            // worldLandmarks
            WritableArray worldWritable = Arguments.createArray();
            if (result.worldLandmarks() != null && !result.worldLandmarks().isEmpty()) {
              for (com.google.mediapipe.tasks.components.containers.Landmark lm : result.worldLandmarks().get(0)) {
                WritableMap m = Arguments.createMap();
                m.putDouble("x", lm.x());
                m.putDouble("y", lm.y());
                m.putDouble("z", lm.z());
                if (lm.visibility().isPresent()) m.putDouble("visibility", lm.visibility().get());
                if (lm.presence().isPresent()) m.putDouble("presence", lm.presence().get());
                worldWritable.pushMap(m);
              }
            }
            payload.putArray("worldLandmarks", worldWritable);

            WritableMap additional = Arguments.createMap();
            additional.putInt("height", processed.getHeight());
            additional.putInt("width", processed.getWidth());
            additional.putDouble("presentationTimeStamp", currentMs);
            additional.putDouble("frameNumber", frameNumber);
            additional.putDouble("startTimestamp", startTs);
            payload.putMap("additionalData", additional);

            if (includeBase64) {
              java.io.ByteArrayOutputStream baos = new java.io.ByteArrayOutputStream();
              processed.compress(Bitmap.CompressFormat.JPEG, jpegQuality, baos);
              String b64 = Base64.encodeToString(baos.toByteArray(), Base64.NO_WRAP);
              payload.putString("frameBase64", b64);
            }
          }

          try {
            onLandmark.invoke(payload);
          } catch (Throwable t) {
            debugLog(onDebug, "onLandmark callback error: " + t);
          }
          framesProcessed++;
          frameNumber++;

          // periodic progress log
          int p = (int)((currentMs * 100L) / Math.max(1, durationMs));
          if (p / 10 > lastLog) {
            lastLog = p / 10;
            debugLog(onDebug, "progress ~" + (lastLog * 10) + "% framesProcessed=" + framesProcessed);
          }
        }

        try { retriever.release(); } catch (Throwable ignore) {}

        WritableMap summary = Arguments.createMap();
        summary.putInt("framesProcessed", framesProcessed);
        summary.putInt("durationMs", durationMs);
        onComplete.invoke(summary);
      } catch (Throwable t) {
        debugLog(onDebug, "processVideo fatal: " + t);
        WritableMap summary = Arguments.createMap();
        summary.putInt("framesProcessed", framesProcessed);
        summary.putInt("durationMs", 0);
        summary.putString("error", String.valueOf(t));
        onComplete.invoke(summary);
      }
    }).start();
  }
}
