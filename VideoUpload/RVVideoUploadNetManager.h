//
//  RVVideoUploadNetManager.h
//  RVSDK
//
//  Created by 黄雄荣 on 2023/11/26.
//  Copyright © 2023 黄雄荣. All rights reserved.
//

#import <Foundation/Foundation.h>


NS_ASSUME_NONNULL_BEGIN

@interface RVVideoUploadInfo : NSObject
/// 文件上传路径
@property (nonatomic, copy) NSString *filePath;
/// 上传ID
@property (nonatomic, copy) NSString *uploadId;
/// 文件分片上传链接数组
@property (nonatomic, strong) NSArray <NSString *> *uploadUrls;

- (instancetype)initWithDict:(NSDictionary *)dict;

@end


//MARK: - RVVideoUploadNetManager

// 获取分片上传视频的urls
#define RV_VIDEO_CREATEUPLOAD_URL   [NSString stringWithFormat:@"https://gsupport.%@/index/getUploadVideoUrls",RVOPENHOST]
// 通知视频分片全部上传完成
#define RV_VIDEO_COMPLETEUPLOAD_URL   [NSString stringWithFormat:@"https://gsupport.%@/index/competeUploadVideo",RVOPENHOST]


// 定义回调
typedef void (^RVVideoUploadFailure)(NSInteger code, NSString * _Nullable msg);//失败
typedef void (^RVVideoUploadSuccess)(NSDictionary * _Nonnull result);//成功


@interface RVVideoUploadNetManager : NSObject

+ (instancetype)sharedManager;

#pragma mark - Upload Video
/// 请求视频分片上传urls
/// - Parameters:
///   - chunks: 分片数量
///   - videoType: 视频类型 mp4 或 mov
///   - success: 成功回调
///   - failure: 失败回调
- (void)requestUploadVideoUrlsWithChunks:(NSUInteger)chunks
                               videoType:(NSString *)videoType
                                 success:(RVVideoUploadSuccess)success
                                 failure:(RVVideoUploadFailure)failure;

/// 上传视频分片数据
/// - Parameters:
///   - partData: 分片数据
///   - uploadUrl: 上传链接
///   - success: 成功回调
///   - failure: 失败回调
- (void)uploadVideoPartData:(NSData *)partData
                  uploadUrl:(NSString *)uploadUrl
                    success:(RVVideoUploadSuccess)success
                    failure:(RVVideoUploadFailure)failure;

/// 通知后台分片上传完毕
/// - Parameters:
///   - uploadId: 上传ID
///   - filePath: 文件路径
///   - success: 成功回调
///   - failure: 失败回调
- (void)notifyVideoUploadCompleteWithUploadId:(NSString *)uploadId
                                     filePath:(NSString *)filePath
                                      success:(RVVideoUploadSuccess)success
                                      failure:(RVVideoUploadFailure)failure;

@end

NS_ASSUME_NONNULL_END
