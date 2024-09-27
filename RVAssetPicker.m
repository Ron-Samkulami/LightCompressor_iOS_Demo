//
//  RVAssetPicker.m
//  RVSDK
//
//  Created by 黄雄荣 on 2023/10/23.
//  Copyright © 2023 黄雄荣. All rights reserved.
//

#import "RVAssetPicker.h"
#import "RVOnlyLog.h"
#import "RVRootViewTool.h"
#import <CoreServices/UTCoreTypes.h>
#import "RVDeviceUtils.h"
#import "RVTempFileManager.h"
#import "RVLocalizeHelper.h"
#import "DeviceMacro.h"
#import "RVPlistHelper.h"

#import "RVVideoCompressTool.h"
#import "RVVideoUploadManager.h"
#import "RVImageUploadManager.h"
#import "RVProgressHUD.h"
#import "NSStringUtils.h"

#define RVSDKTempResources @"RVSDKTempResources"

@interface RVAssetPicker () <UINavigationControllerDelegate, UIImagePickerControllerDelegate>
/// 选择完成回调
@property(nonatomic, copy) void (^completeHandler)(NSURL *url, RVAssetType assetType);
@end

@implementation RVAssetPicker

- (void)dealloc
{
    NSLogWarn(@"%s",__FUNCTION__);
    [[RVTempFileManager sharedManager] cleanTempResource];
}

+ (instancetype)sharedPicker
{
    static id instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

#pragma mark - Public
- (void)showWithCompleteHandler:(void (^)(NSURL *, RVAssetType))completeHandler {
    // 先保存回调
    self.completeHandler = completeHandler;
    // 弹出选择界面
    [self showPicker];
}


#pragma mark - showPicker
/// 显示
- (void)showPicker {
    
    // 先检查相册权限，没有权限不给打开
    NSString *photoLibraryUsageDescription = [RVPlistHelper readValueFromAppPlistForKey:@"NSPhotoLibraryUsageDescription"];
    if (isStringEmpty(photoLibraryUsageDescription)) {
        NSLogWarn(@"Info.plist中未添加 NSPhotoLibraryUsageDescription");
        if (self.completeHandler) {
            self.completeHandler(nil, RVAssetTypeVideo);
        }
        return;
    }
    
    // 通过topViewController显示弹窗
    UIViewController *topVC = [RVRootViewTool getTopViewController];
    
    UIAlertController *alertController = [UIAlertController alertControllerWithTitle:nil message:nil preferredStyle:UIAlertControllerStyleAlert];
    // 图库
    if ([UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypePhotoLibrary]) {
        // 选择图片
        UIAlertAction *libraryPhotoAction = [UIAlertAction actionWithTitle:GetStringByKey(@"choose_photo_text") style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
            [self showPhotoLibraryWithMediaType:RVAssetTypeImage fromViewController:topVC];
        }];
        [alertController addAction:libraryPhotoAction];
        
        // 选择视频
        UIAlertAction *libraryVideoAction = [UIAlertAction actionWithTitle:GetStringByKey(@"choose_video_text") style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
            [self showPhotoLibraryWithMediaType:RVAssetTypeVideo fromViewController:topVC];
        }];
        [alertController addAction:libraryVideoAction];
    }
    
    // 相机，调用前检查Info.plist文件
//    if ([UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypeCamera]) {
//        UIAlertAction *cameraAction = [UIAlertAction actionWithTitle:GetStringByKey(@"camera_text") style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
//            [self showImagePickerWithSourceType:UIImagePickerControllerSourceTypeCamera fromViewController:topVC];
//        }];
//        [alertController addAction:cameraAction];
//    }

    [alertController addAction:[UIAlertAction actionWithTitle:GetStringByKey(@"Cancelled_text") style:UIAlertActionStyleCancel handler:nil]];
    
    [topVC presentViewController:alertController animated:YES completion:nil];
}

- (void)showImagePickerWithSourceType:(UIImagePickerControllerSourceType)sourceType
                   fromViewController:(UIViewController *)sourceVC
{
    UIImagePickerController * imagePickerVC = [[UIImagePickerController alloc] init];
    imagePickerVC.sourceType = sourceType;
    // 支持拍照和录像
    imagePickerVC.mediaTypes = @[(NSString *)kUTTypeMovie, (NSString *)kUTTypeImage];
    // 视频类型最长允许120秒
    imagePickerVC.videoMaximumDuration = self.videoMaximumDuration>0?self.videoMaximumDuration:120;
    // 视频类型最高允许质量，超过的会自动降低质量
    imagePickerVC.videoQuality = UIImagePickerControllerQualityTypeHigh;
    imagePickerVC.delegate = self;
//            imagePickerVC.allowsEditing = YES; // 默认关闭编辑
    [sourceVC presentViewController:imagePickerVC animated:YES completion:nil];
}

/// 根据类型显示相册
- (void)showPhotoLibraryWithMediaType:(RVAssetType)mediaType
                   fromViewController:(UIViewController *)sourceVC
{
    UIImagePickerController * imagePickerVC = [[UIImagePickerController alloc] init];
    imagePickerVC.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
    imagePickerVC.mediaTypes = @[(NSString *)kUTTypeImage];
    if (mediaType == RVAssetTypeVideo) {
        imagePickerVC.mediaTypes = @[(NSString *)kUTTypeMovie];
        // 视频类型最长允许120秒
        imagePickerVC.videoMaximumDuration = self.videoMaximumDuration>0?self.videoMaximumDuration:120;
        imagePickerVC.videoQuality = UIImagePickerControllerQualityTypeHigh;
    }
    imagePickerVC.delegate = self;
//            imagePickerVC.allowsEditing = YES; // 默认关闭编辑
    [sourceVC presentViewController:imagePickerVC animated:YES completion:nil];
}

#pragma mark - UIImagePickerControllerDelegate
/// 取消选择
- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
    UIViewController *topVC = [RVRootViewTool getTopViewController];
    [topVC dismissViewControllerAnimated:YES completion:nil];
}

/// 选择成功调用此方法
- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary<NSString *,id> *)info {
    // 关闭选取界面
    UIViewController *topVC = [RVRootViewTool getTopViewController];
    [topVC dismissViewControllerAnimated:YES completion:nil];
    
    NSLogDebug(@"%@", info);
    // 图片
    /**
     {
         UIImagePickerControllerCropRect = "NSRect: {{0, 0}, {500, 202}}";
         UIImagePickerControllerEditedImage = "<UIImage:0x600003193180 anonymous {500, 202} renderingMode=automatic(original)>";
         UIImagePickerControllerImageURL = "file:///Users/Ron/Library/Developer/CoreSimulator/Devices/EDCE70CC-7BEC-40AA-B216-DA97DB91AE4E/data/Containers/Data/Application/6F640056-FC7C-443A-B51E-72C3A2530E98/tmp/7A1DB95C-7049-42CE-97EF-37CCF37393C2.gif";
         UIImagePickerControllerMediaType = "public.image";
         UIImagePickerControllerOriginalImage = "<UIImage:0x6000031932a0 anonymous {500, 202} renderingMode=automatic(original)>";
         UIImagePickerControllerPHAsset = "<PHAsset: 0x7fe5f5468d70> CD53C97D-B769-41A1-816C-1077FD9F3CB5/L0/001 mediaType=1/64, sourceType=1, (500x202), creationDate=2023-08-28 11:07:04 +0000, location=0, hidden=0, favorite=0, adjusted=0 ";
         UIImagePickerControllerReferenceURL = "assets-library://asset/asset.GIF?id=CD53C97D-B769-41A1-816C-1077FD9F3CB5&ext=GIF";
     }
     */
    // 视频
    /**
     {
         UIImagePickerControllerMediaType = "public.movie";
         UIImagePickerControllerMediaURL = "file:///private/var/mobile/Containers/Data/PluginKitPlugin/D04422F6-2797-45F5-95B7-CA2E44D308BC/tmp/trim.5B2BE0E4-F954-45F4-9BE1-70667635FDB1.MOV";
         UIImagePickerControllerPHAsset = "<PHAsset: 0x102166330> 60C6C3B5-37EA-4063-A594-B63BF5321651/L0/001 mediaType=2/524288, sourceType=1, (1920x1440), creationDate=2023-09-15 07:28:24 +0000, location=0, hidden=0, favorite=0, adjusted=0 ";
         UIImagePickerControllerReferenceURL = "assets-library://asset/asset.MP4?id=60C6C3B5-37EA-4063-A594-B63BF5321651&ext=MP4";
     }
     */
    // 相机拍摄视频
    /**
     {
         UIImagePickerControllerMediaType = "public.movie";
         UIImagePickerControllerMediaURL = "file:///private/var/mobile/Containers/Data/Application/B0A9F284-0EBA-48A8-8599-9EDFA83CEDB8/tmp/71689151419__1AA07A6D-37A0-4D6A-A037-1258054DE7EE.MOV";
     }
     */
    // 相机拍摄照片
    /**
     {
         UIImagePickerControllerMediaMetadata =     {
             DPIHeight = 72;
             DPIWidth = 72;
             Orientation = 6;
             "{Exif}" =         {};  // 拍摄参数
             "{MakerApple}" =         {}; // 不知道是啥
             "{TIFF}" =         {}; // 设备及系统信息
         };
         UIImagePickerControllerMediaType = "public.image";
         UIImagePickerControllerOriginalImage = "<UIImage:0x281264990 anonymous {2448, 3264} renderingMode=automatic>";
     }
     */
    
    // 获取类型
    NSString* mediaType = info[UIImagePickerControllerMediaType];
    NSLogDebug(@"mediaType:%@",mediaType);
    
    if ([mediaType isEqualToString:@"public.movie"]) {
        // 视频类型
        NSURL *mediaURL = info[UIImagePickerControllerMediaURL];
        if (self.completeHandler) {
            self.completeHandler(mediaURL, RVAssetTypeVideo);
        }
        
    } else if ([mediaType isEqualToString:@"public.image"]) {
        // 图片类型
        NSURL *imageURL = info[UIImagePickerControllerImageURL];
//        // 直接拍照时，获取不到 UIImagePickerControllerImageURL，需要自行将图片保存到本地目录，再获取URL
//        if (!imageURL) {
            UIImage *image = info[UIImagePickerControllerOriginalImage];
            if (picker.allowsEditing) {
                image = info[UIImagePickerControllerEditedImage];
            }
            imageURL = [[RVTempFileManager sharedManager] saveImageToTempAsJPEG:image compressionQuality:1.0];
//        }
        NSLogDebug(@"Photo Temp Local Path: %@",imageURL);
        
        if (self.completeHandler) {
            self.completeHandler(imageURL, RVAssetTypeImage);
        }
    }
}


// 获取缩略图或视频首帧
+ (UIImage *)getThumbnailImageWithAsset:(AVAsset *)asset {
    // 获取视频首帧图片保存到沙盒
    NSError *error;
    AVAssetImageGenerator *imageGenrator = [[AVAssetImageGenerator alloc] initWithAsset:asset];
    imageGenrator.appliesPreferredTrackTransform = YES;
    CGImageRef thumbnailImageRef = [imageGenrator copyCGImageAtTime:CMTimeMake(0, 600) actualTime:nil error:&error];
    UIImage *thumbnailImage = [UIImage imageWithCGImage:thumbnailImageRef];
    if (!thumbnailImage) {
        NSLogDebug(@"截取首帧图片失败");
        return nil;
    }
    return thumbnailImage;
}


#pragma mark - debug

+ (void)test {
    
    NSString *callback = @"回调方法名";
    // 压缩分辨率等级 1=low, 2=medium, 3=high
    int presetLevel = 1;
    // 比特率等级 1=very_low, 2=low, 3=normal, 4=high, 5=very_high
    int bitRateLevel = 1;
    // 比特率值，优先级大于比特率等级
    float bitRateInMbps = 2.5;
    // 视频最大时长，单位分钟
    float maxDuration = 2;
    // 视频最大文件，单位MB
    float maxSize = 2;
    // 修改进度条颜色
    [RVProgressHUD setCircularProgressColor:[UIColor redColor]];
    
    RVAssetPicker *picker = [RVAssetPicker sharedPicker];
    picker.videoMaximumDuration = 10;
    
    [picker showWithCompleteHandler:^(NSURL *url, RVAssetType assetType) {
        NSUInteger fileSize = [[RVTempFileManager sharedManager] getfileSize:url];
        NSLogDebug(@"压缩前文件大小：%lu字节", fileSize);
        
        if (fileSize == 0) {
            [self callbackMediaCompressPicker:callback isSuccess:NO message:@"Empty file" assetType:assetType imagePath:nil isImageCompressed:NO videoPath:nil videoDuration:nil videoThumbnailPath:nil];
            return;
        }
        
        if (assetType == RVAssetTypeImage) {
            NSURL *imageURL = url;
            BOOL isImageCompressed = NO;
            if (fileSize > 1024*1024*20) {
                NSLogWarn(@"图片大小不能超过20M");
                //回调失败
                [self callbackMediaCompressPicker:callback isSuccess:NO message:GetStringByKey(@"image_oversize_text") assetType:assetType imagePath:nil isImageCompressed:NO videoPath:nil videoDuration:nil videoThumbnailPath:nil];
                return;
            } else if (fileSize > 1024*1024*4) {
                NSLogDebug(@"图片大小超过4M，进行压缩处理");
                UIImage *image = [UIImage imageWithData:[NSData dataWithContentsOfURL:url]];
                imageURL = [[RVTempFileManager sharedManager] saveImageToTempAsJPEG:image compressionQuality:0.7];
                isImageCompressed = YES;
            } else {}
            
            // 上传图片
            [[RVImageUploadManager sharedManager] uploadImage:imageURL callback:^(BOOL isSuccess, NSString * _Nullable filePath, NSString * _Nullable message) {
                // 返回有效地址才算成功
                isSuccess = isSuccess && isValidString(filePath);
                if (!isSuccess) NSLogWarn(@"图片上传失败：%@", message);
                NSString *msgKey = isSuccess?@"image_upload_success_text":@"image_upload_fail_text";
                // 回调结果
                [self callbackMediaCompressPicker:callback isSuccess:isSuccess message:GetStringByKey(msgKey) assetType:assetType imagePath:filePath isImageCompressed:isImageCompressed videoPath:nil videoDuration:nil videoThumbnailPath:nil];
            }];
            
            
        } else if (assetType == RVAssetTypeVideo) {
            NSLogDebug(@"视频压缩上传");
            // 获取源视频信息
            AVAsset *asset = [AVAsset assetWithURL:url];
            CMTime duration = asset.duration;
            float time = duration.value/duration.timescale;
            NSString *videoDuration = [NSString stringWithFormat:@"%d",(int)time];
            NSLog(@"原视频时长：%f ,转化后%@",time, videoDuration);
            
            // 压缩视频
            [[RVVideoCompressTool sharedTool] compressVideo:url presetLevel:presetLevel bitRateLevel:bitRateLevel bitRateInMbps:bitRateInMbps maxDuration:maxDuration complete:^(NSURL *url) {
                // 上传视频
                RVVideoUploadManager *sharedManager = [RVVideoUploadManager sharedManager];
                [sharedManager uploadVideo:url callback:^(BOOL isSuccess, NSString * _Nullable filePath, NSString * _Nullable message) {
                    if (isSuccess && isValidString(filePath)) {
                        NSString *videoFilePath = filePath;
                        // 获取视频首帧图片
                        UIImage *thumbnailImage = [RVAssetPicker getThumbnailImageWithAsset:asset];
                        NSURL *imageURL = [[RVTempFileManager sharedManager] saveImageToTempAsJPEG:thumbnailImage compressionQuality:0.7];
                        // 上传首帧图片
                        [[RVImageUploadManager sharedManager] uploadImage:imageURL callback:^(BOOL isSuccess, NSString * _Nullable filePath, NSString * _Nullable message) {
                            // 返回有效地址才算成功
                            isSuccess = isSuccess && isValidString(filePath);
                            if (!isSuccess) NSLogWarn(@"视频缩略图上传失败：%@", message);
                            NSString *msgKey = isSuccess?@"video_upload_success_text":@"video_upload_fail_text";
                            // 回调结果
                            [self callbackMediaCompressPicker:callback isSuccess:isSuccess message:GetStringByKey(msgKey) assetType:assetType imagePath:nil isImageCompressed:NO videoPath:videoFilePath videoDuration:videoDuration videoThumbnailPath:filePath];
                        }];
                        
                    } else {
                        // 视频上传失败
                        [self callbackMediaCompressPicker:callback isSuccess:NO message:GetStringByKey(@"video_upload_fail_text") assetType:assetType imagePath:nil isImageCompressed:NO videoPath:nil videoDuration:nil videoThumbnailPath:nil];
                        NSLogWarn(@"视频上传失败, %@", message);
                    }
                }];
                
            } failure:^(NSString *msg) {
                // 视频压缩失败
                [self callbackMediaCompressPicker:callback isSuccess:NO message:GetStringByKey(@"video_compress_fail_text") assetType:assetType imagePath:nil isImageCompressed:NO videoPath:nil videoDuration:nil videoThumbnailPath:nil];
                NSLogWarn(@"视频压缩失败：%@",msg);
            }];
        }
        
        
    }];
}

+ (void)callbackMediaCompressPicker:(NSString *)callback isSuccess:(BOOL)isSuccess message:(NSString *)message assetType:(RVAssetType)assetType imagePath:(NSString *)imagePath isImageCompressed:(BOOL)isImageCompressed videoPath:(NSString *)videoPath videoDuration:(NSString *)videoDuration videoThumbnailPath:(NSString *)videoThumbnailPath
{
    NSString *mediaType = assetType == RVAssetTypeVideo ? @"video" : @"image";
    // 回调给网页
    NSDictionary *data = @{
        @"media_type":mediaType,
        @"image_path":imagePath?:@"",
        @"is_image_compressed":isImageCompressed?@"1":@"0",
        @"video_path":videoPath?:@"",
        @"video_duration":videoDuration?:@"",
        @"video_thumbnail_path":videoThumbnailPath?:@"",
    };
    NSDictionary *callbackParams = @{
        @"msg":message?:@"",
        @"result":isSuccess?@"1":@"0",
        @"data":data
    };
    
    NSLogWarn(@"回调：%@\n", callbackParams);
    
    // 还原进度条颜色
    [RVProgressHUD setCircularProgressColor:nil];
    // 清理临时资源
    [[RVTempFileManager sharedManager] cleanTempResource];
}
@end
