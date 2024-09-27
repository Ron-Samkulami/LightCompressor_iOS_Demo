//
//  RVVideoUploadManager.m
//  RVSDK
//
//  Created by 黄雄荣 on 2023/11/26.
//  Copyright © 2023 黄雄荣. All rights reserved.
//

#import "RVVideoUploadManager.h"
#import "RVFileStream.h"
#import "RVOnlyLog.h"
#import "RVVideoUploadNetManager.h"
#import "RSXToolSet.h"
#import "NSStringUtils.h"
#import "BusinessMacro.h"
#import "RVProgressHUD.h"
#import "RVLocalizeHelper.h"

#define VideoSliceSize 1024*1024*5
/// 上传的queue名
static const char *RVVideoUploadQueueName = "com.sdk.video.upload";

@interface RVVideoUploadManager ()
/// 文件流处理
@property (nonatomic, strong) RVFileStream *fileStream;
/// 并发队列
@property (nonatomic, strong) dispatch_queue_t queue;
/// 是否正在运行
@property (nonatomic, assign) BOOL isRunning;
/// 上传会话信息
@property (nonatomic, strong) RVVideoUploadInfo *uploadInfo;
/// 上传回调
@property (nonatomic, copy) RVVideoUploadCallback uploadCallback;
@end


@implementation RVVideoUploadManager


+ (instancetype)sharedManager {
    static id sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

/**
 视频文件上传现在只在H5中使用，上传过程发生错误中断时，直接删除本地缓存，不做续传处理，因为续传了也没用，H5活动页都已经关了
 */
- (void)uploadVideo:(NSURL *)videoFileUrl callback:(RVVideoUploadCallback)callback {
    
    // 防止上传的时候被多次调用
    if (_isRunning) {
        NSLogInfo(@"RVVideoUploadManager _isRunning = YES");
        return;
    }
    _isRunning = YES;
    
    // 保存回调
    __weak typeof(self) weakSelf = self;
    self.uploadCallback = ^(BOOL isSuccess, NSString * _Nullable filePath, NSString * _Nullable message) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        // 如论结果如何都关闭session
        [strongSelf sessionDealloc];
        callback(isSuccess, filePath, message);
    };
    
    // 将视频文件分片
    NSUInteger chunks = [self cutVideoAndGetChunks:videoFileUrl];
    if (chunks < 1) {
        if (self.uploadCallback) self.uploadCallback(NO, nil, @"Cut file failed");
        return;
    }
    
    // 根据分片数、视频类型，从后台获取分享上传urls
    [[RVVideoUploadNetManager sharedManager] requestUploadVideoUrlsWithChunks:chunks videoType:@"mp4" success:^(NSDictionary * _Nonnull result) {
        NSLogDebug(@"result=%@",result);
        // 转模型
        self.uploadInfo = [[RVVideoUploadInfo alloc] initWithDict:result];
        // 检查返回的上传uploadUrls个数是否等于分片数
        if (self.uploadInfo.uploadUrls.count != chunks) {
            NSLogWarn(@"视频上传链接个数与分片数不匹配");
            if (self.uploadCallback) self.uploadCallback(NO, nil, @"视频分片上传链接个数与分片数不匹配");
            return;
        }
        
        // 更新fileStream 中的uploadId
        self.fileStream.uploadId = self.uploadInfo.uploadId;
        
        // 多线程上传所有分片
        [self uploadFileDataInQueue];
        
    } failure:^(NSInteger code, NSString * _Nullable msg) {
        NSString *errorMessage = [NSString stringWithFormat:@"获取视频分片上传链接失败：%@", msg];
        NSLogWarn(@"%@",errorMessage);
        if (self.uploadCallback) self.uploadCallback(NO, nil, errorMessage);
    }];
    
    
}

/// 将视频文件分片，并返回分片数
- (NSUInteger)cutVideoAndGetChunks:(NSURL *)videoFileUrl {
    // 去掉前缀
    NSString *urlString = videoFileUrl.absoluteString;
    if ([urlString hasPrefix:@"file://"]) {
        urlString  = [urlString stringByReplacingOccurrencesOfString:@"file://" withString:@"" options:NSLiteralSearch range:NSMakeRange(0, 10)];
    }
    //这里先设置了一个假的 uploadId，从后台获取到真正的ID后要做更新
    RVFileStream *fileStream = [[RVFileStream alloc] initWithFilePath:urlString uploadId:@"placeholderId" cutFragmenSize:VideoSliceSize];
    if (!fileStream) {
        return 0;
    }
    self.fileStream = fileStream;
    
    NSUInteger chunks = self.fileStream.streamFragments.count;
    return chunks;
}

#pragma mark - 上传操作
/// 文件上传操作
- (void)uploadFileDataInQueue {
    [RVProgressHUD showCircularProgressWithStatus:GetStringByKey(@"uploading_text") progress:0.01f];
    // 创建一个变量，记录上传成功的分片数量
    __block int uploadedSliceCount = 0;
    // 并发上传
    dispatch_group_t group = dispatch_group_create();
    NSUInteger chunks = self.fileStream.streamFragments.count;
    for (int i = 0; i < chunks; i++) {
        dispatch_group_async(group, self.queue, ^{
            //添加线程锁
            dispatch_semaphore_t sema = dispatch_semaphore_create(0);
            
            // 执行一个上传请求，没个请求内部会做错误处理及重试
            [self uploadVideoSliceAtIndex:i complete:^(BOOL uploadSuccess) {
                if (uploadSuccess) {
                    uploadedSliceCount += 1;
                    // 分片上传成功，刷新进度
                    [RVProgressHUD showCircularProgressWithStatus:GetStringByKey(@"uploading_text") progress:(float)uploadedSliceCount/chunks];
                    NSLogDebug(@"上传进度：%d/%zd", uploadedSliceCount, chunks);
                } else {
                    NSLogWarn(@"第%d分片上传失败",i);
                }
                // 无论成功失败，都解开线程锁
                dispatch_semaphore_signal(sema);
            }];
           
            // 等待线程锁解开
            dispatch_semaphore_wait(sema, DISPATCH_TIME_FOREVER);
            
        });
    }
    
    //完成全部任务
    dispatch_group_notify(group, dispatch_get_main_queue(), ^{
        // 已完成的分片数量 = 分片数量，则已完成
        if (uploadedSliceCount == chunks) {
//            NSLogDebug(@"All Slice upload success：%@", [NSDate date]);
            // 上报上传完成
            [self notifyVideoUploadComplete];
            
        } else {
            [RVProgressHUD showErrorWithStatus:nil];
            if (self.uploadCallback) self.uploadCallback(NO, nil, @"Some slice upload failed");
        }
        
        
    });
}

- (void)uploadVideoSliceAtIndex:(NSUInteger)index complete:(void(^)(BOOL uploadSuccess))complete
{
    RVStreamFragment *fragment = self.fileStream.streamFragments[index];
    if (fragment.status) {
        //已经上传成功的不再处理
        NSLogDebug(@"i=%lu,fragmentStatus == YES",(unsigned long)index);
        if (complete) complete(YES);
        return;
    }
    
    NSString *uploadUrl = self.uploadInfo.uploadUrls[index];
    if (isStringEmpty(uploadUrl)) {
        // 对应的上传链接为空
        NSLogDebug(@"i=%lu,uploadUrl is empty ",(unsigned long)index);
        if (complete) complete(NO);
        return;
    }
    
    @autoreleasepool {
        // 根据文件片信息来读取文件数据流(通过offset+size来定位)
        NSData *partData = [self.fileStream multiThreadReadDataOfFragment:fragment];
        if (!partData) {
            NSLogWarn(@"partData为空");
            if (complete) complete(NO);
            return;
        }
        
        // 上传，如果网络失败，会延时5s重试两次
        [self uploadPartData:partData uploadUrl:uploadUrl currentRepeatTimes:0 success:^(NSDictionary * _Nonnull result) {
            NSLogDebug(@"uploadPartData success=%@",result);
            // 记录单片上传成功
            fragment.status = YES;
            // 回调成功
            if (complete) complete(YES);
            
        } failure:^(NSInteger code, NSString * _Nullable msg) {
            NSLogDebug(@"uploadPartData failed=%@",msg);
            // 回调失败
            if (complete) complete(NO);
        }];
    }
    
}

//网络上传，网络失败会重试两次
- (void)uploadPartData:(NSData *)partData
             uploadUrl:(NSString *)uploadUrl
     currentRepeatTimes:(int)times
               success:(RVVideoUploadSuccess)success
               failure:(RVVideoUploadFailure)failure
{
    static int const maxTimes = 3;//一共3次
    if (times >= maxTimes) {
        NSLogInfo(@"网络超时超过重试次数，返回失败");
        if (failure) failure(NETWORK_ERR_CODE, @"网络超时超过重试次数，返回失败");
        return;
    }
    NSLogInfo(@"uploadPartData times=%d",times);
    [[RVVideoUploadNetManager sharedManager] uploadVideoPartData:partData uploadUrl:uploadUrl success:success failure:^(NSInteger code, NSString * _Nullable msg) {
        //网络失败的话重试2次
        if (code == NETWORK_ERR_CODE) {
            //延迟重试
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                //递归调用
                [self uploadPartData:partData uploadUrl:uploadUrl currentRepeatTimes:times+1 success:success failure:failure];
            });
            
        } else {
            if (failure) failure(code,msg);
        }
    }];
    
}

/// 通知分片上传完成
- (void)notifyVideoUploadComplete
{
    NSString *uploadId = self.uploadInfo.uploadId;
    NSString *filePath = self.uploadInfo.filePath;
    [[RVVideoUploadNetManager sharedManager] notifyVideoUploadCompleteWithUploadId:uploadId filePath:filePath success:^(NSDictionary * _Nonnull result) {
        [RVProgressHUD dismiss];
        NSLogDebug(@"notifyVideoUploadComplete success： %@", result);
        if (self.uploadCallback) self.uploadCallback(YES, filePath, @"上传成功");
        
    } failure:^(NSInteger code, NSString * _Nullable msg) {
        [RVProgressHUD dismiss];
        NSLogDebug(@"notifyVideoUploadComplete fail： %@", msg);
        if (self.uploadCallback) self.uploadCallback(NO, nil, @"通知分片上传完成失败");
    }];
}


#pragma mark - Getter
- (dispatch_queue_t)queue {
    if (!_queue) {
        _queue = dispatch_queue_create(RVVideoUploadQueueName, DISPATCH_QUEUE_CONCURRENT);
    }
    return _queue;
}


#pragma mark - 内存释放

- (void)sessionDealloc {
    NSLogDebug(@"upload sessionDealloc");
    _fileStream = nil;
    _uploadInfo = nil;
    _queue = NULL;
    _isRunning = NO;
}


//MARK: - DEBUG

+ (void)test
{
    [[RVVideoUploadManager sharedManager] uploadFileDataInQueue];
}

@end
