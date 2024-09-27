//
//  RVVideoCompressTool.h
//  RVSDK
//
//  Created by 黄雄荣 on 2023/10/23.
//  Copyright © 2023 黄雄荣. All rights reserved.
//
/**
 视频编码器
 1、压缩视频并转换格式
 */

#import <Foundation/Foundation.h>

#define Max_duration 120        // 压缩输出的最大时长
#define Max_frameRate 30.f      // 压缩输出的最大帧率

@interface RVVideoCompressTool : NSObject

+ (instancetype)sharedTool;

/// 将视频文件进行压缩
/// - Parameters:
///   - videoUrl: 视频本地地址
///   - presetLevel: 分辨率等级
///   - bitRateLevel: 比特率等级
///   - bitRateInMbps: 比特率值，单位Mbps
///   - maxDuration: 最大输出时长，单位s
///   - complete: 完成回调
///   - failure: 失败回调

- (void)compressVideo:(NSURL *)videoUrl
          presetLevel:(int)presetLevel
         bitRateLevel:(int)bitRateLevel
        bitRateInMbps:(float)bitRateInMbps
          maxDuration:(int)maxDuration
             complete:(void (^)(NSURL * url))complete
             failure:(void (^)(NSString *msg))failure;


@end


