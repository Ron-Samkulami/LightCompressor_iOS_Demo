//
//  RVTempFileManager.h
//  RVSDK
//
//  Created by 黄雄荣 on 2023/11/16.
//  Copyright © 2023 黄雄荣. All rights reserved.
//
/**
 临时文件管理器
 */
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface RVTempFileManager : NSObject

- (instancetype)init NS_UNAVAILABLE;

/// 临时资源目录
@property (nonatomic, copy, readonly) NSString *sdkTempResourcesPath;

+ (instancetype)sharedManager;

/// 清理临时文件
- (void)cleanTempResource;


#pragma mark - Image
/// 以JPEG格式临时保存图片，并获取图片路径
- (NSString *)saveImageToTempAsJPEG:(UIImage *)image;

/// 以JPEG格式临时保存图片，并获取URL
/// - Parameters:
///   - image: 图片对象
///   - compressionQuality: 压缩率 [0, 1]
- (NSURL *)saveImageToTempAsJPEG:(UIImage *)image compressionQuality:(CGFloat)compressionQuality;

#pragma mark - Video

/// 创建视频临时保存路径
- (NSURL *)createTempUrlForVideo;


#pragma mark - Download Image
/// 根据URL下载图片
- (void)downloadImageFromURL:(NSURL *)url completion:(void (^)(UIImage *image))completion;

#pragma mark - Utils
/// 获取文件大小，单位字节
- (NSUInteger)getfileSize:(NSURL *)fileUrl;

@end

NS_ASSUME_NONNULL_END
