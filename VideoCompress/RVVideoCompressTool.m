//
//  RVVideoCompressTool.m
//  RVSDK
//
//  Created by 黄雄荣 on 2023/10/23.
//  Copyright © 2023 黄雄荣. All rights reserved.
//

#import "RVVideoCompressTool.h"
#import "RVOnlyLog.h"
#import "NSStringUtils.h"
#import <RVSDK/RVSDK-Swift.h>
#import "RVProgressHUD.h"
#import "RVTempFileManager.h"
#import "RVLocalizeHelper.h"

@implementation RVVideoCompressTool

- (void)dealloc
{
    NSLogWarn(@"%s",__FUNCTION__);
}

+ (instancetype)sharedTool {
    static id instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

/// 压缩视频，传入本地视频地址
- (void)compressVideo:(NSURL *)videoUrl presetLevel:(int)presetLevel bitRateLevel:(int)bitRateLevel bitRateInMbps:(float)bitRateInMbps maxDuration:(int)maxDuration complete:(void (^)( NSURL *))complete failure:(void (^)(NSString *))failure {
    // 创建路径用于存放输出视频
    NSURL *destinationVideoUrl = [[RVTempFileManager sharedManager] createTempUrlForVideo];
    
    __block float currentProgress = 0.0f;
    // 调用压缩
    [[RVLightCompressor shared] compressVideoWithSourceVideo:videoUrl destination:destinationVideoUrl presetLevel:presetLevel bitRateLevel:bitRateLevel bitRateInMbps:bitRateInMbps maxDuration:maxDuration progressHandler:^(NSProgress * _Nonnull progress) {
        if (progress.fractionCompleted > currentProgress) {
            // 展示压缩进度
            [RVProgressHUD showCircularProgressWithStatus:[NSString stringWithFormat:@"%@ ",GetStringByKey(@"video_compressing_text")] progress:currentProgress];
            currentProgress += 0.01f; // 控制进度展示颗粒度
        }
        
    } completionHandler:^(NSURL * _Nullable url) {
        [RVProgressHUD showCircularProgressWithStatus:[NSString stringWithFormat:@"%@ ",GetStringByKey(@"video_compressing_text")] progress:1.0];
        [RVProgressHUD dismiss];
        // 回调
        if (complete) {
            complete(url);
        }
        
    } failHandler:^(NSError * _Nullable error) {
        [RVProgressHUD dismiss];
        NSLogError(@"压缩视频时出错：%@", error.domain);
        
        if (failure) {
            failure(error.domain);
        }
    }];
}


@end
