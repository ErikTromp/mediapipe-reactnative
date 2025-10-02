#import <React/RCTViewManager.h>
#import "TsMediapipe-Bridging-Header.h"
#import "React/RCTEventEmitter.h"
#import <React/RCTBridgeModule.h>

@interface RCT_EXTERN_MODULE(TsMediapipeViewManager, RCTViewManager)

RCT_EXPORT_VIEW_PROPERTY(width, NSNumber)
RCT_EXPORT_VIEW_PROPERTY(height, NSNumber)

RCT_EXPORT_VIEW_PROPERTY(onLandmark, RCTDirectEventBlock)

RCT_EXTERN_METHOD(switchCamera)

RCT_EXPORT_VIEW_PROPERTY(face, BOOL)
RCT_EXPORT_VIEW_PROPERTY(leftArm, BOOL)
RCT_EXPORT_VIEW_PROPERTY(rightArm, BOOL)
RCT_EXPORT_VIEW_PROPERTY(leftWrist, BOOL)
RCT_EXPORT_VIEW_PROPERTY(rightWrist, BOOL)
RCT_EXPORT_VIEW_PROPERTY(torso, BOOL)
RCT_EXPORT_VIEW_PROPERTY(leftLeg, BOOL)
RCT_EXPORT_VIEW_PROPERTY(rightLeg, BOOL)
RCT_EXPORT_VIEW_PROPERTY(leftAnkle, BOOL)
RCT_EXPORT_VIEW_PROPERTY(rightAnkle, BOOL)
RCT_EXPORT_VIEW_PROPERTY(frameLimit, NSNumber)
@end

@interface RCT_EXTERN_MODULE(MediapipeVideoModule, NSObject)
RCT_EXTERN_METHOD(processVideo:(NSString *)uri
                  options:(NSDictionary *)options
                  onLandmark:(RCTResponseSenderBlock)onLandmark
                  onComplete:(RCTResponseSenderBlock)onComplete)
RCT_EXTERN_METHOD(cancelProcessVideo)
RCT_EXTERN_METHOD(processVideoWithDebug:(NSString *)uri
                  options:(NSDictionary *)options
                  onLandmark:(RCTResponseSenderBlock)onLandmark
                  onComplete:(RCTResponseSenderBlock)onComplete
                  onDebug:(RCTResponseSenderBlock)onDebug)
@end
