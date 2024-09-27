//
//  RVTempFileManager.m
//  RVSDK
//
//  Created by 黄雄荣 on 2023/11/16.
//  Copyright © 2023 黄雄荣. All rights reserved.
//

#import "RVTempFileManager.h"
#import "RVOnlyLog.h"

#define RVSDKTempResources @"RVSDKTempResources"

@interface RVTempFileManager ()
@property (nonatomic, copy, readwrite) NSString *sdkTempResourcesPath;
@end

@implementation RVTempFileManager

- (void)dealloc
{
    NSLogWarn(@"%s",__FUNCTION__);
    [self cleanTempResource];
}

+ (instancetype)sharedManager
{
    static id instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

#pragma mark - Clean
/// 清理临时目录
- (void)cleanTempResource {
    NSString *tmpPath = [self sdkTempResourcesPath];
    NSFileManager *fileManeger = [NSFileManager defaultManager];
    NSArray *content = [fileManeger contentsOfDirectoryAtPath:tmpPath error:NULL];
    
    if (!content || content.count == 0) {
        return;
    }
    
    NSLogDebug(@"清理SDK临时资源目录：%@ \n%@", tmpPath, content);
    NSEnumerator *e = [content objectEnumerator];
    
    NSString *fileName = nil;
    while ((fileName = [e nextObject])) {
        NSString *fileFullPath = [NSString stringWithFormat:@"%@/%@",tmpPath,fileName];
        NSError *error;
        [fileManeger removeItemAtPath:fileFullPath error:&error];
        if (error) {
            NSLogWarn(@"删除临时文件时出错: %@ \n文件完整路径: %@", error.domain, fileFullPath);
        }
    }
}

#pragma mark - Image
/// 以JPEG格式临时保存图片，并获取图片路径
- (NSString *)saveImageToTempAsJPEG:(UIImage *)image {
    NSURL *fileUrl = [self saveImageToTempAsJPEG:image compressionQuality:0.7];
    if (!fileUrl) {
        return nil;
    }
    // 去掉 file:// 前缀
    NSString *filePath = fileUrl.absoluteString;
    if ([filePath hasPrefix:@"file://"]) {
        filePath  = [filePath stringByReplacingOccurrencesOfString:@"file://" withString:@"" options:NSLiteralSearch range:NSMakeRange(0, 10)];
    }
    NSLogDebug(@"照片临时保存路径 %@",filePath);
    return filePath;
}

/// 以JPEG格式临时保存图片，并获取URL
- (NSURL *)saveImageToTempAsJPEG:(UIImage *)image compressionQuality:(CGFloat)compressionQuality {
    if (!image) {
        return nil;
    }
    // 保存到临时路径
    NSString *sdkTmpPath = [self sdkTempResourcesPath];
    
    // 转换成jpg格式
    NSData *data = UIImageJPEGRepresentation(image, compressionQuality);
    // 以uuid命名
    NSString *filePath = [NSString stringWithFormat:@"%@/tmp_image_%@.%@", sdkTmpPath, [NSUUID UUID].UUIDString, @"jpg"];
    // 写入文件需要添加file:// 前缀
    NSURL *fileUrl = [NSURL fileURLWithPath:filePath];
    [data writeToURL:fileUrl atomically:YES];
    
    NSLogDebug(@"图片临时保存路径 %@",fileUrl);
    return fileUrl;
}

#pragma mark - Video
/// 创建视频临时保存路径
- (NSURL *)createTempUrlForVideo {
    // 获取临时目录
    NSString *sdkTmpPath = [self sdkTempResourcesPath];
    // 拼接目标URL
    NSString *videoFileName = [NSString stringWithFormat:@"%@.mp4",[NSUUID UUID].UUIDString];
    return [NSURL fileURLWithPathComponents:@[sdkTmpPath, videoFileName]];
}

#pragma mark - Getter
/// 临时资源目录
- (NSString *)sdkTempResourcesPath {
    if (!_sdkTempResourcesPath) {
        _sdkTempResourcesPath = [NSString stringWithFormat:@"%@%@",NSTemporaryDirectory(),RVSDKTempResources];
    }
    
    // 目录不存在时，创建
    if (![self isDirectoryExist:_sdkTempResourcesPath]) {
        [self createDirectory:_sdkTempResourcesPath];
    }
    return _sdkTempResourcesPath;
}

#pragma mark - private

/// 判断文件夹是否存在
- (BOOL)isDirectoryExist:(NSString *)path {
    NSFileManager *fileManeger = [NSFileManager defaultManager];
    BOOL isDirectory = YES;
    BOOL fileExist = [fileManeger fileExistsAtPath:path isDirectory:&isDirectory];
    if (fileExist && isDirectory) {
        return YES;
    }
    return NO;
}

/// 创建文件夹
- (void)createDirectory:(NSString *)path {
    NSFileManager *fileManeger = [NSFileManager defaultManager];
    NSLogDebug(@"创建SDK临时资源目录：%@", path);
    NSError *error;
    [fileManeger createDirectoryAtPath:path withIntermediateDirectories:NO attributes:@{} error:&error];
    if (error) {
        NSLogError(@"创建SDK临时资源目录时出错：%@", error.domain);
    }
}

#pragma mark - Download Image
- (void)downloadImageFromURL:(NSURL *)url completion:(void (^)(UIImage *image))completion {
    NSURLSessionTask *downloadTask = [[NSURLSession sharedSession] dataTaskWithURL:url completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        if (data) {
            UIImage *image = [UIImage imageWithData:data];
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(image);
            });
            
        } else {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(nil);
            });
            
        }
    }];
    [downloadTask resume];
}

#pragma mark - Utils
/// 获取文件大小，单位字节
- (NSUInteger)getfileSize:(NSURL *)fileUrl {
    NSString *path = fileUrl.absoluteString;
    // 去掉 file:// 前缀
    if ([path hasPrefix:@"file://"]) {
        path  = [path stringByReplacingOccurrencesOfString:@"file://" withString:@"" options:NSLiteralSearch range:NSMakeRange(0, 10)];
    }
    
    NSFileManager *fileMgr = [NSFileManager defaultManager];
    if (![fileMgr fileExistsAtPath:path]) {
        NSLogWarn(@"所选的媒体文件不存在：%@",path);
        return 0;
    }
    
    NSDictionary *attr = [fileMgr attributesOfItemAtPath:path error:nil];
    NSUInteger fileSize = (NSUInteger)attr.fileSize;
    return fileSize;
}

@end
