//
//  ofAVFoundationVideoPlayer.h
//  Created by Lukasz Karluk on 06/07/14.
//	Merged with code by Sam Kronick, James George and Elie Zananiri.
//

//----------------------------------------------------------
#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <Accelerate/Accelerate.h>
#import <CoreMedia/CoreMedia.h>

#import <HapInAVFoundation/HapInAVFoundation.h>

//----------------------------------------------------------
#include <TargetConditionals.h>
#if (TARGET_OS_IPHONE_SIMULATOR) || (TARGET_OS_IPHONE) || (TARGET_IPHONE)
#define TARGET_IOS
#else
#define TARGET_OSX
#endif


// so we are independend from oF in this class
typedef enum _HapInAVFoundationPlayerLoopType{
    HapInAVFoundationPlayerLoopType_None=0x01,
    HapInAVFoundationPlayerLoopType_Palindrome=0x02,
    HapInAVFoundationPlayerLoopType_Normal=0x03
} HapInAVFoundationPlayerLoopType;


//---------------------------------------------------------- video player.
@interface HapInAVFoundationPlayer : NSObject {
    
    AVPlayer * _player;
    AVAsset * _asset;
    AVPlayerItem * _playerItem;
    
    AVAssetTrack * _hapTrack;
    
    AVPlayerItemHapDXTOutput * _videoOutput;
    
    id timeObserver;
    
    HapInAVFoundationPlayerLoopType loop;
    
    BOOL bReady;
    BOOL bLoaded;
    BOOL bPlayStateBeforeLoad;
    BOOL bUpdateFirstFrame;
    BOOL bNewFrame;
    BOOL bPlaying;
    BOOL bFinished;
    BOOL bAutoPlayOnLoad;
    BOOL bIsUnloaded;
    
    float speed;
    
    NSLock* asyncLock;
    NSCondition* deallocCond;
}


@property (nonatomic, retain) HapDecoderFrame *currentFrame;


- (BOOL)loadWithFile:(NSString*)file async:(BOOL)bAsync;
- (BOOL)loadWithPath:(NSString*)path async:(BOOL)bAsync;
- (BOOL)loadWithURL:(NSURL*)url async:(BOOL)bAsync;

- (void)unloadVideo;

- (void)update;

- (void)play;
- (void)pause;
- (void)togglePlayPause;

- (void)stepByCount:(long)frames;

- (void)seekToStart;
- (void)seekToEnd;
- (void)seekToTime:(CMTime)time;
- (void)seekToTime:(CMTime)time withTolerance:(CMTime)tolerance;

- (BOOL)isReady;
- (BOOL)isLoaded;
- (BOOL)isPlaying;
- (BOOL)isNewFrame;
- (BOOL)isFinished;

- (NSInteger)getWidth;
- (NSInteger)getHeight;
- (CMTime)getCurrentTime;
- (double)getCurrentTimeInSec;
- (CMTime)getDuration;
- (double)getDurationInSec;
- (int)getDurationInFrames;
- (int)getCurrentFrameNum;
- (float)getFrameRate;

- (void)setFrame:(int)frame;
- (void)setPosition:(float)position;
- (float)getPosition;
- (void)setLoop:(HapInAVFoundationPlayerLoopType)loop;
- (HapInAVFoundationPlayerLoopType)getLoop;
- (void)setSpeed:(float)speed;
- (float)getSpeed;
- (void)setAutoplay:(BOOL)bAutoplay;
- (BOOL)getAutoplay;
- (void)close;

@end