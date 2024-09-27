//
//  RVImageUploadNetManager.h
//  RVSDK
//
//  Created by 黄雄荣 on 2023/11/28.
//  Copyright © 2023 黄雄荣. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface RVImageUploadInfo : NSObject
/// 文件上传标识，一般是图片名字+字节大小
@property (nonatomic, copy) NSString *context;
/// 待上传的分片序号，一般从1开始
@property (nonatomic, strong) NSArray <NSString *> *unUploadChunks;

@end

// 获取图片分片数量
#define RV_IMAGE_CREATEUPLOAD_URL   [NSString stringWithFormat:@"https://gsupport.%@/index/getUnUploadChunks",RVOPENHOST]
// 上传图片分片
#define RV_IMAGE_UPLOADSLICE_URL   [NSString stringWithFormat:@"https://gsupport.%@/index/uploadImg2",RVOPENHOST]
// 通知上传图片完成
#define RV_IMAGE_COMPLETEUPLOAD_URL   [NSString stringWithFormat:@"https://gsupport.%@/index/mkFile",RVOPENHOST]


// 定义回调
typedef void (^RVImageUploadFailure)(NSInteger code, NSString * _Nullable msg);//失败
typedef void (^RVImageUploadSuccess)(NSDictionary * _Nonnull result);//成功

@interface RVImageUploadNetManager : NSObject

+ (instancetype)sharedManager;


/// 创建图片上传任务，从后台获取各个分片序号
/// - Parameters:
///   - chunks: 分片数量
///   - context: 上传任务标识，一般是 图片名字+字节大小
///   - success: 成功回调
///   - failure: 失败回调
- (void)createImageUploadWithChunks:(NSUInteger)chunks
                            context:(NSString *)context
                            success:(RVImageUploadSuccess)success
                            failure:(RVImageUploadFailure)failure;

/// 上传单个分片数据
/// - Parameters:
///   - partData: 分片数据
///   - context: 上传任务标识
///   - chunk: 上传分片序号标识
///   - success: 成功回调
///   - failure: 失败回调
- (void)uploadPartData:(NSData *)partData
               context:(NSString *)context
                 chunk:(NSString *)chunk
               success:(RVImageUploadSuccess)success
               failure:(RVImageUploadFailure)failure;

/// 通知后台分片上传完毕
/// - Parameters:
///   - chunks: 分片数量
///   - context: 上传任务标识，一般是 图片名字+字节大小
///   - success: 成功回调
///   - failure: 失败回调
- (void)notifyImageUploadCompleteWithChunks:(NSUInteger)chunks
                                    context:(NSString *)context
                                    success:(RVImageUploadSuccess)success
                                    failure:(RVImageUploadFailure)failure;
@end

NS_ASSUME_NONNULL_END
