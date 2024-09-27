//
//  RVLightCompressor.swift
//  RVSDK
//
//  Created by 黄雄荣 on 2023/11/21.
//  Copyright © 2023 黄雄荣. All rights reserved.
//

import Foundation
import AVFoundation

@objc
public enum PresetLevel: Int {
    case low        = 1
    case medium     = 2
    case high       = 3
}

@objc
public enum BitRateLevel: Int {
    case very_low   = 1
    case low        = 2
    case medium     = 3
    case high       = 4
    case very_high  = 5
}

@objc
public enum RVVideoPreset: Int {
    case RVVideoPreset1920x1080 = 1
    case RVVideoPreset1280x720  = 2
    case RVVideoPreset960x540   = 3
}

@objc
public class RVLightCompressor: NSObject {
    
    private let MIN_BITRATE_IMMBPS = Float(2.0)        // 比特率最低值
    private let BITRATE_BASE_LEVEL = 3              // 比特率基准等级
    private let BITRATE_MAX_LEVEL = 5               // 比特率最高等级
    private let BITRATE_LEVEL_DELTA_IMMBPS = Float(0.5)      // 比特率级差

    private var compression: Compression?
    
    private override init() {}
    
    @objc
    public static let shared = RVLightCompressor()
    
    @objc
    func cancelCompresse() {
        compression?.cancel = true
    }
    
    @objc
    public func compressVideo(sourceVideo: URL, destination:URL, presetLevel:PresetLevel, bitRateLevel:BitRateLevel, bitRateInMbps:Float, maxDuration:Int, progressHandler:((Progress) -> Void)?, completionHandler:@escaping ((_ resultUrl: URL?) -> Void), failHandler:@escaping ((_ error: Error?) -> Void)) {
        
        // 计算分辨率
        let videoSize = self.getOutputVideoSize(sourceVideo, presetLevel)
        
        // 计算比特率
        var bitRate = self.getBitRateInMbps(presetLevel, bitRateLevel)
        // 如果传入了比特率值，直接使用比特率值，但不能低于最低值： 2000 * 1000
        if bitRateInMbps > 0.0 {
            bitRate = max(bitRateInMbps, MIN_BITRATE_IMMBPS)
        }
        
        let config = LightCompressor.Video.Configuration.init(quality: VideoQuality.very_high, isMinBitrateCheckEnabled:false, videoBitrateInMbps: bitRate, disableAudio: false, keepOriginalResolution: false, videoSize: videoSize , maxDuration: maxDuration)
        let video = LightCompressor.Video.init(source: sourceVideo, destination: destination, configuration: config)
        
        compression = LightCompressor().compressVideo(videos: [video],
                                                    progressQueue: .main,
                                                    progressHandler: progressHandler,
                                                    completion: { [weak self] result in
            guard let `self` = self else { return }
            
            switch result {
            case .onSuccess(let index, let url):
                print("Compress Video Success")
                completionHandler(url)
                
            case .onStart:
                print("Compress Video Start")
                
            case .onFailure(let index, let error):
                print("Compress Video Failed")
                failHandler(error)
                
            case .onCancelled:
                print("Compress Video Cancelled")
                failHandler(nil)
            }
        })
    }
    
    
    /**
    计算比特率
    
    |  分辨率等级     |   VERY_ LOW码率值     |    LOW码率值         |   NORMAL码率值(基准)    |    HIGH码率值      |   VERY HIGH码率值
    |--------------------|---------------------------------|---------------------------|------------------------------------|-------------------------|-----------------------------
    |  LOW             |   2000*1000kps            |    2500*1000kps     |       3000*1000kps            |   3500*1000kps   |   4000*1000kps
    |-------------------|--------------------------------|---------------------------|------------------------------------|-------------------------|-----------------------------
    |  MEDIUM      |   3000*1000kps           |   3500*1000kps     |      4000*1000kps             |    4500*1000kps   |  5000*1000kps
    |------------------|--------------------------------|--------------------------|------------------------------------|--------------------------|-----------------------------
    |  HIGH          |   5000*1000kps           |   5500*1000kps     |       6000*1000kps            |   6500*1000kps    |   7000*1000kps
    */
    func getBitRateInMbps(_ presetLevel: PresetLevel, _ bitRateLevel: BitRateLevel) -> Float {
        // 先按分辨率取基准值
        var bitRate = Float(0)
        switch presetLevel {
        case .high:
            bitRate = 6
        case .medium:
            bitRate = 4
        case .low:
            bitRate = 3
        default:
            bitRate = 3
        }
        
        // 再按比特率等级调整
        if bitRateLevel.rawValue > 0 {
            let validBitRateLevel = min(bitRateLevel.rawValue, BITRATE_MAX_LEVEL)
            bitRate += Float(validBitRateLevel - BITRATE_BASE_LEVEL) * BITRATE_LEVEL_DELTA_IMMBPS;
        }
        return bitRate
    }
    
    /**
     按等级获取压缩分辨率
     
     |          等级               |             分辨率
     |---------------------------|----------------------------------------
     |      大于等于 3         |       1920x1080
     |---------------------------|----------------------------------------
     |            2                  |       1280x720
     |---------------------------|----------------------------------------
     |      小于等于 1         |       960x540
     |---------------------------|----------------------------------------
     */
    func getOutputVideoSize(_ sourceVideo: URL ,_ presetLevel: PresetLevel) -> CGSize? {
        let videoAsset = AVURLAsset(url: sourceVideo)
        guard let videoTrack = videoAsset.tracks(withMediaType: AVMediaType.video).first else {
            return nil
        }
        
        let naturalSize = videoTrack.naturalSize
        let width = naturalSize.width
        let height = naturalSize.height

        var videoSize = CGSize(width: width, height: height)
//        print("原始分辨率，width:\(videoSize.width) height:\(videoSize.height)")
        
        // 输出分辨率
        var targetPresetSize = Double(960)
        switch presetLevel.rawValue {
        case 3...:
            targetPresetSize = 1920
        case 2:
            targetPresetSize = 1280
        default:
            targetPresetSize = 960
        }
        // 长边大于targetPresetSize时，长边压缩到targetPresetSize，短边按比例缩放；
        // 长边不大于targetPresetSize时，使用原参数
        if width > height {
            videoSize = CGSize(width: min(targetPresetSize, width), height: min(targetPresetSize * (height / width), height))
        } else {
            videoSize = CGSize(width: min(targetPresetSize * (width / height), width), height: min(targetPresetSize, height))
        }
//        print("压缩分辨率，width:\(videoSize.width) height:\(videoSize.height)")
        return videoSize
        
    }
    
}
