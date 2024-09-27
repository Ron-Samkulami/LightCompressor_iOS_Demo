//
//  RVVideoUploadManager.h
//  RVSDK
//
//  Created by 黄雄荣 on 2023/11/26.
//  Copyright © 2023 黄雄荣. All rights reserved.
//

#import <Foundation/Foundation.h>


NS_ASSUME_NONNULL_BEGIN

/// 视频上传回调，isSuccess: 是否成功，filePath: 上传地址，message: 信息
typedef void (^RVVideoUploadCallback)(BOOL isSuccess, NSString *__nullable filePath, NSString *__nullable message);

@interface RVVideoUploadManager : NSObject

+ (instancetype)sharedManager;

/// 上传视频文件
/// - Parameter videoFileUrl: 视频文件的本地路径
- (void)uploadVideo:(NSURL *)videoFileUrl callback:(RVVideoUploadCallback)callback;

@end

NS_ASSUME_NONNULL_END
