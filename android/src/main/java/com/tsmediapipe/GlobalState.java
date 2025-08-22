package com.tsmediapipe;

public class GlobalState {
  public static boolean isFaceEnabled = false;
  public static boolean isTorsoEnabled = false;
  public static boolean isLeftArmEnabled = false;
  public static boolean isRightArmEnabled = false;
  public static boolean isLeftWristEnabled = false;
  public static boolean isRightWristEnabled = false;
  public static boolean isLeftLegEnabled = false;
  public static boolean isRightLegEnabled = false;
  public static boolean isLeftAnkleEnabled = false;
  public static boolean isRightAnkleEnabled = false;
  public static boolean isDrawOverlayEnabled = true;
  public static String currentModelType = "full";
  
  // Performance optimization settings
  public static int inputResolution = 640;
  public static int detectionFrequency = 10; // milliseconds
  public static int delegate = 0; // 0 = CPU, 1 = GPU

  public static String orientation = "portrait";
}
