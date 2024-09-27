//
//  RVAssetPicker.h
//  RVSDK
//
//  Created by 黄雄荣 on 2023/10/23.
//  Copyright © 2023 黄雄荣. All rights reserved.
//

/**
 图片视频选取器
 开启web服务将处理后的文件路径以http形式返回给前端访问
 ps: 目前仅做为Demo调试
 */
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>

/// 文件类型
typedef NS_ENUM(NSInteger, RVAssetType) {
    RVAssetTypeImage,
    RVAssetTypeVideo,
};

@interface RVAssetPicker : NSObject
/// 视频最大时长
@property(nonatomic, assign) NSTimeInterval videoMaximumDuration;

- (instancetype)init NS_UNAVAILABLE;

+ (instancetype)sharedPicker;


/// 显示图片视频选择器
/// - Parameter completeHandler: 回调
- (void)showWithCompleteHandler:(void (^)(NSURL *url, RVAssetType assetType))completeHandler;

/// 获取缩略图或视频首帧
+ (UIImage *)getThumbnailImageWithAsset:(AVAsset *)asset;

@end

