//
//  ViewController.m
//  VideoCaptureDemo
//
//  Created by huangyibiao on 16/6/9.
//  Copyright © 2016年 huangyibiao. All rights reserved.
//

#import "ViewController.h"
#import <AVFoundation/AVAsset.h>
#import <AVFoundation/AVFoundation.h>
#import <AssetsLibrary/AssetsLibrary.h>
#import <AVFoundation/AVAssetImageGenerator.h>
#import <MobileCoreServices/MobileCoreServices.h>
#import <CoreMedia/CoreMedia.h>

@interface ViewController () <UIImagePickerControllerDelegate, UINavigationControllerDelegate>

@property (weak, nonatomic) IBOutlet UIImageView *centerFrameImageView;
@property (weak, nonatomic) IBOutlet UILabel *videoDurationLabel;
@property (nonatomic, assign) BOOL shouldAsync;

@end

@implementation ViewController

- (void)viewDidLoad {
  [super viewDidLoad];
  
}

- (IBAction)onRecordVideo:(id)sender {
  // 7.0
  AVAuthorizationStatus authStatus = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo];
  if (authStatus == AVAuthorizationStatusRestricted
      || authStatus == AVAuthorizationStatusDenied) {
    NSLog(@"摄像头已被禁用，您可在设置应用程序中进行开启");
    return;
  }
  
  if ([UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypeCamera]) {
    UIImagePickerController *picker = [[UIImagePickerController alloc] init];
    picker.delegate = self;
    picker.allowsEditing = YES;
    picker.sourceType = UIImagePickerControllerSourceTypeCamera;
    picker.videoQuality = UIImagePickerControllerQualityType640x480; //录像质量
    picker.videoMaximumDuration = 5 * 60.0f; // 限制视频录制最多不超过5分钟
    picker.mediaTypes = @[(NSString *)kUTTypeMovie];
    [self presentViewController:picker animated:YES completion:NULL];
    self.shouldAsync = YES;
  } else {
    NSLog(@"手机不支持摄像");
  }
}

- (IBAction)onSelectLocalVideo:(id)sender {
  // 7.0
  AVAuthorizationStatus authStatus = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo];
  if (authStatus == AVAuthorizationStatusRestricted
      || authStatus == AVAuthorizationStatusDenied) {
    NSLog(@"摄像头已被禁用，您可在设置应用程序中进行开启");
    return;
  }
  
  if ([UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypeSavedPhotosAlbum]) {
    UIImagePickerController *picker = [[UIImagePickerController alloc] init];
    picker.delegate = self;
    picker.allowsEditing = YES;
    picker.sourceType = UIImagePickerControllerSourceTypeSavedPhotosAlbum;
    picker.mediaTypes = @[(NSString *)kUTTypeMovie];
    [self presentViewController:picker animated:YES completion:NULL];
    self.shouldAsync = NO;
  } else {
    NSLog(@"手机不支持摄像");
  }
}


#pragma  mark - UIImagePickerControllerDelegate
// 录制视频完成后要执行的代理方法
- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary *)info {
  [picker dismissViewControllerAnimated:YES completion:^{
    // for fixing iOS 8.0 problem that frame changed when open camera to record video.
    self.tabBarController.view.frame  = [[UIScreen mainScreen] bounds];
    [self.tabBarController.view layoutIfNeeded];
  }];
  
  NSURL *videoURL = [info objectForKey:UIImagePickerControllerMediaURL];
  ALAssetsLibrary *library = [[ALAssetsLibrary alloc] init];
  dispatch_async(dispatch_get_global_queue(0, 0), ^{
    // 判断相册是否兼容视频，兼容才能保存到相册
    if ([library videoAtPathIsCompatibleWithSavedPhotosAlbum:videoURL]) {
      [library writeVideoAtPathToSavedPhotosAlbum:videoURL completionBlock:^(NSURL *assetURL, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
          AVURLAsset *videoAsset = [[AVURLAsset alloc] initWithURL:assetURL options:nil];
          Float64 duration = CMTimeGetSeconds(videoAsset.duration);
          self.videoDurationLabel.text = [NSString stringWithFormat:@"视频时长：%.0f秒",
                                          duration];
          if (self.shouldAsync) {
            __weak __typeof(self) weakSelf = self;
            // Get center frame image asyncly
            [self centerFrameImageWithVideoURL:videoURL completion:^(UIImage *image) {
              weakSelf.centerFrameImageView.image = image;
            }];
          } else {
            // 同步获取中间帧图片
            UIImage *image = [self frameImageFromVideoURL:videoURL];
            self.centerFrameImageView.image = image;
          }
          
          // Begin to compress and export the video to the output path
          NSString *name = [[NSDate date] description];
          name = [NSString stringWithFormat:@"%@.mp4", name];
          [self compressVideoWithVideoURL:videoURL savedName:name completion:^(NSString *savedPath) {
            if (savedPath) {
              NSLog(@"Compressed successfully. path: %@", savedPath);
            } else {
              NSLog(@"Compressed failed");
            }
          }];
        });
      }];
    }
  });
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker{
  [picker dismissViewControllerAnimated:YES completion:^{
    // for fixing iOS 8.0 problem that frame changed when open camera to record video.
    self.tabBarController.view.frame  = [[UIScreen mainScreen]bounds];
    [self.tabBarController.view layoutIfNeeded];
  }];
}

// Get the video's center frame as video poster image
- (UIImage *)frameImageFromVideoURL:(NSURL *)videoURL {
  // result
  UIImage *image = nil;
  
  // AVAssetImageGenerator
  AVAsset *asset = [AVAsset assetWithURL:videoURL];
  AVAssetImageGenerator *imageGenerator = [[AVAssetImageGenerator alloc] initWithAsset:asset];
  imageGenerator.appliesPreferredTrackTransform = YES;
  
  // calculate the midpoint time of video
  Float64 duration = CMTimeGetSeconds([asset duration]);
  // 取某个帧的时间，参数一表示哪个时间（秒），参数二表示每秒多少帧
  // 通常来说，600是一个常用的公共参数，苹果有说明:
  // 24 frames per second (fps) for film, 30 fps for NTSC (used for TV in North America and
  // Japan), and 25 fps for PAL (used for TV in Europe).
  // Using a timescale of 600, you can exactly represent any number of frames in these systems
  CMTime midpoint = CMTimeMakeWithSeconds(duration / 2.0, 600);
  
  // get the image from
  NSError *error = nil;
  CMTime actualTime;
  // Returns a CFRetained CGImageRef for an asset at or near the specified time.
  // So we should mannully release it
  CGImageRef centerFrameImage = [imageGenerator copyCGImageAtTime:midpoint
                                                       actualTime:&actualTime
                                                            error:&error];
  
  if (centerFrameImage != NULL) {
    image = [[UIImage alloc] initWithCGImage:centerFrameImage];
    // Release the CFRetained image
    CGImageRelease(centerFrameImage);
  }
  
  return image;
}

// 异步获取帧图片，可以一次获取多帧图片
- (void)centerFrameImageWithVideoURL:(NSURL *)videoURL completion:(void (^)(UIImage *image))completion {
  // AVAssetImageGenerator
  AVAsset *asset = [AVAsset assetWithURL:videoURL];
  AVAssetImageGenerator *imageGenerator = [[AVAssetImageGenerator alloc] initWithAsset:asset];
  imageGenerator.appliesPreferredTrackTransform = YES;
  
  // calculate the midpoint time of video
  Float64 duration = CMTimeGetSeconds([asset duration]);
  // 取某个帧的时间，参数一表示哪个时间（秒），参数二表示每秒多少帧
  // 通常来说，600是一个常用的公共参数，苹果有说明:
  // 24 frames per second (fps) for film, 30 fps for NTSC (used for TV in North America and
  // Japan), and 25 fps for PAL (used for TV in Europe).
  // Using a timescale of 600, you can exactly represent any number of frames in these systems
  CMTime midpoint = CMTimeMakeWithSeconds(duration / 2.0, 600);
  
  // 异步获取多帧图片
  NSValue *midTime = [NSValue valueWithCMTime:midpoint];
  [imageGenerator generateCGImagesAsynchronouslyForTimes:@[midTime] completionHandler:^(CMTime requestedTime, CGImageRef  _Nullable image, CMTime actualTime, AVAssetImageGeneratorResult result, NSError * _Nullable error) {
    if (result == AVAssetImageGeneratorSucceeded && image != NULL) {
      UIImage *centerFrameImage = [[UIImage alloc] initWithCGImage:image];
      dispatch_async(dispatch_get_main_queue(), ^{
        if (completion) {
          completion(centerFrameImage);
        }
      });
    } else {
      dispatch_async(dispatch_get_main_queue(), ^{
        if (completion) {
          completion(nil);
        }
      });
    }
  }];
}

- (void)compressVideoWithVideoURL:(NSURL *)videoURL
                        savedName:(NSString *)savedName
                       completion:(void (^)(NSString *savedPath))completion {
  // Accessing video by URL
  AVURLAsset *videoAsset = [[AVURLAsset alloc] initWithURL:videoURL options:nil];
  
  // Find compatible presets by video asset.
  NSArray *presets = [AVAssetExportSession exportPresetsCompatibleWithAsset:videoAsset];
  
  // Begin to compress video
  // Now we just compress to low resolution if it supports
  // If you need to upload to the server, but server does't support to upload by streaming,
  // You can compress the resolution to lower. Or you can support more higher resolution.
  if ([presets containsObject:AVAssetExportPreset640x480]) {
    AVAssetExportSession *session = [[AVAssetExportSession alloc] initWithAsset:videoAsset  presetName:AVAssetExportPreset640x480];
    
    NSString *doc = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents"];
    NSString *folder = [doc stringByAppendingPathComponent:@"HYBVideos"];
    BOOL isDir = NO;
    BOOL isExist = [[NSFileManager defaultManager] fileExistsAtPath:folder isDirectory:&isDir];
    if (!isExist || (isExist && !isDir)) {
      NSError *error = nil;
      [[NSFileManager defaultManager] createDirectoryAtPath:folder
                                withIntermediateDirectories:YES
                                                 attributes:nil
                                                      error:&error];
      if (error == nil) {
        NSLog(@"目录创建成功");
      } else {
        NSLog(@"目录创建失败");
      }
    }
    
    NSString *outPutPath = [folder stringByAppendingPathComponent:savedName];
    session.outputURL = [NSURL fileURLWithPath:outPutPath];
    
    // Optimize for network use.
    session.shouldOptimizeForNetworkUse = true;
    
    NSArray *supportedTypeArray = session.supportedFileTypes;
    if ([supportedTypeArray containsObject:AVFileTypeMPEG4]) {
      session.outputFileType = AVFileTypeMPEG4;
    } else if (supportedTypeArray.count == 0) {
      NSLog(@"No supported file types");
      return;
    } else {
      session.outputFileType = [supportedTypeArray objectAtIndex:0];
    }
    
    // Begin to export video to the output path asynchronously.
    [session exportAsynchronouslyWithCompletionHandler:^{
      if ([session status] == AVAssetExportSessionStatusCompleted) {
        dispatch_async(dispatch_get_main_queue(), ^{
          if (completion) {
            completion([session.outputURL path]);
          }
        });
      } else {
        dispatch_async(dispatch_get_main_queue(), ^{
          if (completion) {
            completion(nil);
          }
        });
      }
    }];
  }
}

@end
