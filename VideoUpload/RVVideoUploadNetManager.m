//
//  RVVideoUploadNetManager.m
//  RVSDK
//
//  Created by 黄雄荣 on 2023/11/26.
//  Copyright © 2023 黄雄荣. All rights reserved.
//

#import "RVVideoUploadNetManager.h"
#import "RVRequestManager.h"
#import "RVResponseParser.h"
#import "RSXConfig.h"
#import "BusinessMacro.h"

#import "NSStringUtils.h"

@implementation RVVideoUploadInfo

- (instancetype)initWithDict:(NSDictionary *)dict {
    if (self = [super init]) {
        if (![dict isKindOfClass:[NSDictionary class]]) {
            return nil;
        }
        
        NSString *filePath = dict[@"file_path"];
        _filePath = nil;
        if (isValidString(filePath)) {
            _filePath = filePath;
        }
        
        NSString *uploadId = dict[@"upload_id"];
        _uploadId = nil;
        if (isValidString(uploadId)) {
            _uploadId = uploadId;
        }
        
        NSArray *uploadUrls = dict[@"upload_urls"];
        _uploadUrls = nil;
        if (uploadUrls.count > 0) {
            _uploadUrls = uploadUrls;
        }
        
    }
    return self;
}

@end

@implementation RVVideoUploadNetManager

+ (instancetype)sharedManager
{
    static id sharedInstance = Nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

#pragma mark - Upload Video

/// 请求视频分片上传urls
- (void)requestUploadVideoUrlsWithChunks:(NSUInteger)chunks
                               videoType:(NSString *)videoType
                                 success:(RVVideoUploadSuccess)success
                                 failure:(RVVideoUploadFailure)failure
{
    RSXConfig *config = [RSXConfig sharedConfig];
    NSMutableDictionary *mDic = [config getBaseInfomation];
    
    [mDic setObject:[NSString stringWithFormat:@"%zd",chunks] forKey:@"chunks"];
    [mDic setObject:videoType?:@"mp4" forKey:@"video_type"];
    
    NSString *urlString = RV_VIDEO_CREATEUPLOAD_URL;
    
    [[RVRequestManager sharedManager] POST:urlString parameters:mDic success:^(id successResponse) {

        RVResponseParser *parser = [[RVResponseParser alloc] initWithURL:urlString];
        [parser parseResponseObject:successResponse];

        if (parser.code == 1) {
            if(success) success(parser.resultData);
        } else {
            if(failure) failure(parser.code, parser.message);
        }
    } failure:^(NSError *error) {

        if(failure) failure(NETWORK_ERR_CODE, error.localizedDescription?:@"");
    }];
}

/// 上传视频分片数据（PUT）
- (void)uploadVideoPartData:(NSData *)partData
                  uploadUrl:(NSString *)uploadUrl
                    success:(RVVideoUploadSuccess)success
                    failure:(RVVideoUploadFailure)failure
{
    NSString *urlString = uploadUrl;
    
    AFRVSDKHTTPSessionManager *manager = [RVRequestManager sharedManager].sessionManager;

    NSError *error;
    NSMutableURLRequest *request = [manager.requestSerializer requestWithMethod:@"PUT" URLString:urlString parameters:nil error:&error];

    [request setHTTPBody:partData];
    
    // 使用Data task上传，也可以使用普通task
    NSURLSessionDataTask *task = [manager dataTaskWithRequest:request uploadProgress:nil downloadProgress:nil completionHandler:^(NSURLResponse * _Nonnull response, id  _Nullable responseObject, NSError * _Nullable error) {
        if (error) {
            if (failure) {
                failure(error.code, error.domain);
            }
            return;
        }

        if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
            NSInteger statusCode = [(NSHTTPURLResponse *)response statusCode];
            if (statusCode == 200) {
                if(success) success(@{});
            }
        }
    }];
    [task resume];
}

/// 通知后台分片上传完毕
- (void)notifyVideoUploadCompleteWithUploadId:(NSString *)uploadId
                                     filePath:(NSString *)filePath
                                      success:(RVVideoUploadSuccess)success
                                      failure:(RVVideoUploadFailure)failure
{
    RSXConfig *config = [RSXConfig sharedConfig];
    NSMutableDictionary *mDic = [config getBaseInfomation];
    
    [mDic setObject:uploadId?:@"" forKey:@"uploadId"];
    [mDic setObject:filePath?:@"" forKey:@"filePath"];
    
    NSString *urlString = RV_VIDEO_COMPLETEUPLOAD_URL;
    
    [[RVRequestManager sharedManager] POST:urlString parameters:mDic success:^(id successResponse) {
        RVResponseParser *parser = [[RVResponseParser alloc] initWithURL:urlString];
        [parser parseResponseObject:successResponse];

        if (parser.code == 1) {
            if(success) success(parser.resultData);
        } else {
            if(failure) failure(parser.code, parser.message);
        }
        
    } failure:^(NSError *error) {
        if(failure) failure(NETWORK_ERR_CODE, error.localizedDescription?:@"");
    }];
}

@end
