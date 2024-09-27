//
//  RVImageUploadManager.m
//  RVSDK
//
//  Created by 黄雄荣 on 2023/11/28.
//  Copyright © 2023 黄雄荣. All rights reserved.
//

#import "RVImageUploadManager.h"
#import "RVFileStream.h"
#import "RVOnlyLog.h"
#import "RVImageUploadNetManager.h"
#import "RVProgressHUD.h"
#import "BusinessMacro.h"
#import "RVLocalizeHelper.h"

/// 分片大小
#define ImageSliceSize 1024*200
/// 上传的queue名
static const char *RVImageUploadQueueName = "com.sdk.image.upload";


@interface RVImageUploadManager ()
/// 文件流处理
@property (nonatomic, strong) RVFileStream *fileStream;
/// 并发队列
@property (nonatomic, strong) dispatch_queue_t queue;
/// 是否正在运行
@property (nonatomic, assign) BOOL isRunning;
/// 待上传的图片信息
@property (nonatomic, strong) RVImageUploadInfo *uploadInfo;
/// 上传回调
@property (nonatomic, copy) RVImageUploadCallback uploadCallback;
@end

@implementation RVImageUploadManager

+ (instancetype)sharedManager {
    static id sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

/// 上传图片
- (void)uploadImage:(NSURL *)imageFileUrl callback:(RVImageUploadCallback)callback {
    // 防止上传的时候被多次调用
    if (_isRunning) {
        NSLogInfo(@"RVImageUploadManager _isRunning = YES");
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
    
    // 将图片分片
    NSUInteger chunks = [self cutImageAndGetChunks:imageFileUrl];
    if (chunks < 1) {
        if (self.uploadCallback) self.uploadCallback(NO, nil, @"Cut file failed");
        return;
    }
    
    // 创建上传文件的标识，名字+大小
    NSString *context = [NSString stringWithFormat:@"%@%lu",self.fileStream.fileName,self.fileStream.fileSize];
    self.uploadInfo = [[RVImageUploadInfo alloc] init];
    self.uploadInfo.context = context;
    
    [[RVImageUploadNetManager sharedManager] createImageUploadWithChunks:chunks context:context success:^(NSDictionary * _Nonnull result) {
        NSLogDebug(@"result=%@",result);
        //
        NSArray *unUploadChunks = result[@"UnUploadChunks"];
        if (unUploadChunks.count > 0) {
            self.uploadInfo.unUploadChunks = unUploadChunks;
        }
        
        // 检查返回的上传uploadUrls个数是否等于分片数
        if (self.uploadInfo.unUploadChunks.count != chunks) {
            NSString *msg = @"图片待上传分片个数与实际分片数不匹配";
            NSLogWarn(@"%@",msg);
            if (self.uploadCallback) self.uploadCallback(NO, nil, msg);
            return;
        }
        
        // 多线程上传所有分片
        [self uploadFileDataInQueue];
        
    } failure:^(NSInteger code, NSString * _Nullable msg) {
        NSString *errorMessage = [NSString stringWithFormat:@"获取图片分片上传索引失败：%@", msg];
        NSLogWarn(@"%@",errorMessage);
        if (self.uploadCallback) self.uploadCallback(NO, nil, errorMessage);
    }];
    
}

/// 将图片文件分片，并返回分片数
- (NSUInteger)cutImageAndGetChunks:(NSURL *)imageUrl {
    // 去掉前缀
    NSString *urlString = imageUrl.absoluteString;
    if ([urlString hasPrefix:@"file://"]) {
        urlString  = [urlString stringByReplacingOccurrencesOfString:@"file://" withString:@"" options:NSLiteralSearch range:NSMakeRange(0, 10)];
    }
    //这里先设置了一个假的 uploadId，从后台获取到真正的ID后要做更新
    RVFileStream *fileStream = [[RVFileStream alloc] initWithFilePath:urlString uploadId:@"placeholderId" cutFragmenSize:ImageSliceSize];
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
            [self uploadImageSliceAtIndex:i complete:^(BOOL uploadSuccess) {
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
        // 通过已完成的分片数量核对整体是否完成
        if (uploadedSliceCount == chunks) {
            NSLogInfo(@"所有分片上传完成：%@", [NSDate date]);
            // 通知分片上传完成
            [self notifyImageUploadComplete];
            
        } else {
            [RVProgressHUD showErrorWithStatus:nil];
            if (self.uploadCallback) self.uploadCallback(NO, nil, @"部分分片上传失败");
        }
        
    });
}

- (void)uploadImageSliceAtIndex:(NSUInteger)index complete:(void(^)(BOOL uploadSuccess))complete
{
    RVStreamFragment *fragment = self.fileStream.streamFragments[index];
    if (fragment.status) {
        //已经上传成功的不再处理
        NSLogDebug(@"i=%lu,fragmentStatus == YES",(unsigned long)index);
        if (complete) complete(YES);
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
        
        NSString *context = self.uploadInfo.context;
        NSString *chunk = [NSString stringWithFormat:@"%@",self.uploadInfo.unUploadChunks[index]];
        
        // 上传，如果网络失败，会延时5s重试两次
        [self uploadPartData:partData context:context chunk:chunk currentRepeatTimes:0 success:^(NSDictionary * _Nonnull result) {
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
               context:(NSString *)context
                 chunk:(NSString *)chunk
     currentRepeatTimes:(int)times
               success:(RVImageUploadSuccess)success
               failure:(RVImageUploadFailure)failure
{
    static int const maxTimes = 3;//一共3次
    if (times >= maxTimes) {
        NSLogInfo(@"网络超时超过重试次数，返回失败");
        if (failure) failure(NETWORK_ERR_CODE, @"网络超时超过重试次数，返回失败");
        return;
    }
    NSLogInfo(@"uploadPartData times=%d",times);
    
    [[RVImageUploadNetManager sharedManager] uploadPartData:partData context:context chunk:chunk success:success failure:^(NSInteger code, NSString * _Nullable msg) {
        //网络失败的话重试2次
        if (code == NETWORK_ERR_CODE) {
            //延迟重试
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                //递归调用
                [self uploadPartData:partData context:context chunk:chunk currentRepeatTimes:times+1 success:success failure:failure];
            });
            
        } else {
            if (failure) failure(code,msg);
        }
    }];
    
}

/// 通知分片上传完成
- (void)notifyImageUploadComplete
{
    NSString *context = self.uploadInfo.context;
    NSUInteger chunks = self.fileStream.streamFragments.count;
    
    [[RVImageUploadNetManager sharedManager] notifyImageUploadCompleteWithChunks:chunks context:context success:^(NSDictionary * _Nonnull result) {
        [RVProgressHUD dismiss];
        NSLogDebug(@"notifyImageUploadComplete success： %@", result);
        // 从返回数据解析 图片地址
        NSArray *imageUrls = result[@"IMG_URL"];
        if ([imageUrls isKindOfClass:[NSArray class]] && imageUrls.count > 0) {
            NSString *imagePath = imageUrls.firstObject;
            if (self.uploadCallback) self.uploadCallback(YES, imagePath, @"上传成功");
        } else {
            if (self.uploadCallback) self.uploadCallback(NO, nil, @"分片上传完成，但返回的上传路径为空");
        }
        
    } failure:^(NSInteger code, NSString * _Nullable msg) {
        [RVProgressHUD dismiss];
        NSLogDebug(@"notifyImageUploadComplete fail： %@", msg);
        if (self.uploadCallback) self.uploadCallback(NO, nil, @"通知分片上传完成失败");
    }];
}

#pragma mark - Getter
- (dispatch_queue_t)queue {
    if (!_queue) {
        _queue = dispatch_queue_create(RVImageUploadQueueName, DISPATCH_QUEUE_CONCURRENT);
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


@end
