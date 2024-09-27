//
//  RVImageUploadNetManager.m
//  RVSDK
//
//  Created by 黄雄荣 on 2023/11/28.
//  Copyright © 2023 黄雄荣. All rights reserved.
//

#import "RVImageUploadNetManager.h"
#import "RVRequestManager.h"
#import "RVResponseParser.h"
#import "RSXConfig.h"
#import "BusinessMacro.h"

@implementation RVImageUploadInfo

@end

@implementation RVImageUploadNetManager

+ (instancetype)sharedManager
{
    static id sharedInstance = Nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

- (void)createImageUploadWithChunks:(NSUInteger)chunks
                            context:(NSString *)context
                            success:(RVImageUploadSuccess)success
                            failure:(RVImageUploadFailure)failure {
    
    RSXConfig *config = [RSXConfig sharedConfig];
    NSMutableDictionary *mDic = [config getBaseInfomation];
    
    [mDic setObject:[NSString stringWithFormat:@"%zd",chunks] forKey:@"chunks"];
    [mDic setObject:context?:@"" forKey:@"context"];
    
    NSString *urlString = RV_IMAGE_CREATEUPLOAD_URL;
    
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

/// 上传单个分片
- (void)uploadPartData:(NSData *)partData
               context:(NSString *)context
                 chunk:(NSString *)chunk
               success:(RVImageUploadSuccess)success
               failure:(RVImageUploadFailure)failure
{
    NSMutableDictionary *mDic = [[NSMutableDictionary alloc] init];
    [mDic setObject:context?:@"" forKey:@"context"];
    [mDic setObject:chunk?:@"" forKey:@"chunk"];

    NSString *urlString = RV_IMAGE_UPLOADSLICE_URL;
    
    AFRVSDKHTTPSessionManager *manager = [RVRequestManager sharedManager].sessionManager;
    
    NSError *error;
    NSURLRequest *request = [manager.requestSerializer multipartFormRequestWithMethod:@"POST" URLString:urlString parameters:mDic constructingBodyWithBlock:^(id<AFRVSDKMultipartFormData>  _Nonnull formData) {
        [formData appendPartWithFileData:partData name:@"file" fileName:@"fileName" mimeType:@"multipart/form-data"];
    } error:&error];
    
    // 使用Data task上传
    NSURLSessionDataTask *task = [manager dataTaskWithRequest:request uploadProgress:nil downloadProgress:nil completionHandler:^(NSURLResponse * _Nonnull response, id  _Nullable responseObject, NSError * _Nullable error) {
        if (error) {
            if (failure) {
                failure(error.code, error.domain);
            }
            return;
        }
        
        RVResponseParser *parser = [[RVResponseParser alloc] initWithURL:urlString];
        [parser parseResponseObject:responseObject];

        if (parser.code == 1) {
           if(success) success(parser.resultData);
        } else {
           if(failure) failure(parser.errorCode,parser.message);
        }
    }];
    [task resume];
    
}


/// 通知后台分片上传完毕
- (void)notifyImageUploadCompleteWithChunks:(NSUInteger)chunks
                                    context:(NSString *)context
                                    success:(RVImageUploadSuccess)success
                                    failure:(RVImageUploadFailure)failure {
    RSXConfig *config = [RSXConfig sharedConfig];
    NSMutableDictionary *mDic = [config getBaseInfomation];
    
    [mDic setObject:[NSString stringWithFormat:@"%zd",chunks] forKey:@"chunks"];
    [mDic setObject:context?:@"" forKey:@"context"];
    
    NSString *urlString = RV_IMAGE_COMPLETEUPLOAD_URL;
    
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
