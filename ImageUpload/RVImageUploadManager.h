//
//  RVImageUploadManager.h
//  RVSDK
//
//  Created by 黄雄荣 on 2023/11/28.
//  Copyright © 2023 黄雄荣. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 图片上传回调，isSuccess: 是否成功，filePath: 上传地址，message: 信息
typedef void (^RVImageUploadCallback)(BOOL isSuccess, NSString *__nullable filePath, NSString *__nullable message);

@interface RVImageUploadManager : NSObject

+ (instancetype)sharedManager;

/// 上传图片
/// - Parameter imageFileUrl: 图片的本地路径
- (void)uploadImage:(NSURL *)imageFileUrl callback:(RVImageUploadCallback)callback;

@end

NS_ASSUME_NONNULL_END
