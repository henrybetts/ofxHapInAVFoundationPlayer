//
//  ofAVFoundationVideoPlayer.m
//  Created by Lukasz Karluk on 06/07/14.
//	Merged with code by Sam Kronick, James George and Elie Zananiri.
//

#import "HapInAVFoundationPlayer.h"

#define IS_OS_6_OR_LATER    ([[[UIDevice currentDevice] systemVersion] floatValue] >= 6.0)



static NSString * const kTracksKey = @"tracks";
static NSString * const kStatusKey = @"status";
static NSString * const kRateKey = @"rate";

//---------------------------------------------------------- video player.
@implementation HapInAVFoundationPlayer

@synthesize currentFrame = _currentFrame;


static const void *ItemStatusContext = &ItemStatusContext;
static const void *PlayerRateContext = &ItemStatusContext;


- (id)init {
    self = [super init];
    if(self) {
        
        _player = nil;
        _videoOutput = nil;
        _asset = nil;
        _hapTrack = nil;
        _playerItem = nil;
        _currentFrame = nil;
        
        asyncLock = [[NSLock alloc] init];
        deallocCond = nil;
        
        timeObserver = nil;
        
        speed = 1.0;
        
        bReady = NO;
        bLoaded = NO;
        bPlayStateBeforeLoad = NO;
        bUpdateFirstFrame = YES;
        bNewFrame = NO;
        bPlaying = NO;
        bFinished = NO;
        bAutoPlayOnLoad = NO;
        loop = HapInAVFoundationPlayerLoopType_None;
        bIsUnloaded = NO;
        
    }
    return self;
}




//---------------------------------------------------------- cleanup / dispose.
- (void)dealloc
{

    [self unloadVideo];
    
    
    // release locks
    [asyncLock release];
    
    if (deallocCond != nil) {
        [deallocCond release];
        deallocCond = nil;
    }
    
    
    [super dealloc];
}



//---------------------------------------------------------- load / unload.
- (BOOL)loadWithFile:(NSString*)file async:(BOOL)bAsync{
    NSArray * fileSplit = [file componentsSeparatedByString:@"."];
    NSURL * fileURL = [[NSBundle mainBundle] URLForResource:[fileSplit objectAtIndex:0]
                                              withExtension:[fileSplit objectAtIndex:1]];
    
    return [self loadWithURL:fileURL async:bAsync];
}

- (BOOL)loadWithPath:(NSString*)path async:(BOOL)bAsync{
    NSURL * fileURL = [NSURL fileURLWithPath:path];
    return [self loadWithURL:fileURL async:bAsync];
}

- (BOOL)loadWithURL:(NSURL*)url async:(BOOL)bAsync {
    
    @autoreleasepool {
    
    NSDictionary *options = @{(id)AVURLAssetPreferPreciseDurationAndTimingKey:@(YES)};
    AVURLAsset* asset = [[AVURLAsset alloc] initWithURL:url options:options];
    
    if(asset == nil) {
        NSLog(@"error loading asset: %@", [url description]);
        return NO;
    }
    
    
    // store state
    BOOL _bReady = bReady;
    BOOL _bLoaded = bLoaded;
    BOOL _bPlayStateBeforeLoad = bPlayStateBeforeLoad;
    
    BOOL __block bSuccess = NO;
    
    // set internal state
    bIsUnloaded = NO;
    bReady = NO;
    bLoaded = NO;
    bPlayStateBeforeLoad = NO;
    
    // going to load
    dispatch_semaphore_t sema = dispatch_semaphore_create(0);
    dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    
    dispatch_async(queue, ^{
        [asset loadValuesAsynchronouslyForKeys:[NSArray arrayWithObject:kTracksKey] completionHandler:^{
            
            @autoreleasepool{
            
            NSError * error = nil;
            AVKeyValueStatus status = [asset statusOfValueForKey:kTracksKey error:&error];
            
            if(status != AVKeyValueStatusLoaded) {
                NSLog(@"error loading asset tracks: %@", [error localizedDescription]);
                // reset
                bReady = _bReady;
                bLoaded = _bLoaded;
                bPlayStateBeforeLoad = _bPlayStateBeforeLoad;
                if(bAsync == NO){
                    dispatch_semaphore_signal(sema);
                }
                return;
            }
            
            CMTime duration = [asset duration];
            
            if(CMTimeCompare(duration, kCMTimeZero) == 0) {
                NSLog(@"track loaded with zero duration.");
                // reset
                bReady = _bReady;
                bLoaded = _bLoaded;
                bPlayStateBeforeLoad = _bPlayStateBeforeLoad;
                if(bAsync == NO){
                    dispatch_semaphore_signal(sema);
                }
                return;
            }
            
            // TODO
            // why not reading infinite media?
            // how about playing back HLS streams?
            if(isfinite(CMTimeGetSeconds(duration)) == NO) {
                NSLog(@"track loaded with infinite duration.");
                // reset
                bReady = _bReady;
                bLoaded = _bLoaded;
                bPlayStateBeforeLoad = _bPlayStateBeforeLoad;
                if(bAsync == NO){
                    dispatch_semaphore_signal(sema);
                }
                return;
            }
            
            if(![asset containsHapVideoTrack]) {
                NSLog(@"no hap video tracks found.");
                // reset
                bReady = _bReady;
                bLoaded = _bLoaded;
                bPlayStateBeforeLoad = _bPlayStateBeforeLoad;
                if(bAsync == NO){
                    dispatch_semaphore_signal(sema);
                }
                return;
            }
            
            //------------------------------------------------------------
            //------------------------------------------------------------ use asset
            // good to go
            [asyncLock lock];
            
            if (bIsUnloaded) {
                // player was unloaded before we could load everything
                bIsUnloaded = NO;
                if(bAsync == NO){
                    dispatch_semaphore_signal(sema);
                }
                [asyncLock unlock];
                return;
            }
            
            // clean up
            [self unloadVideoAsync];     // unload video if one is already loaded.
            
            bIsUnloaded = NO;
            
            // set asset
            _asset = asset;
            
            _hapTrack = [[asset hapVideoTracks] firstObject];
            [_hapTrack retain];
                
            NSLog(@"video loaded at %li x %li @ %f fps", (long)[self getWidth], (long)[self getHeight], [self getFrameRate]);
            
            
            //------------------------------------------------------------ create player item.
            AVPlayerItem* playerItem = [[AVPlayerItem playerItemWithAsset:_asset] retain];

            if (!playerItem) {
                NSLog(@"could not create AVPlayerItem");
                if(bAsync == NO){
                    dispatch_semaphore_signal(sema);
                }
                [asyncLock unlock];
                return;
            }
            
            //------------------------------------------------------------ player item.
            _playerItem = playerItem;
            [_playerItem addObserver:self
                              forKeyPath:kStatusKey
                                 options:0
                                 context:&ItemStatusContext];
            
            NSNotificationCenter* notificationCenter = [NSNotificationCenter defaultCenter];
            [notificationCenter addObserver:self
                                   selector:@selector(playerItemDidReachEnd)
                                       name:AVPlayerItemDidPlayToEndTimeNotification
                                     object:_playerItem];
            
            //AVPlayerItemPlaybackStalledNotification only exists from OS X 10.9 or iOS 6.0 and up
#if (__MAC_OS_X_VERSION_MIN_REQUIRED >= 1090) || (__IPHONE_OS_VERSION_MIN_REQUIRED >= 60000)
            [notificationCenter addObserver:self
                                   selector:@selector(playerItemDidStall)
                                       name:AVPlayerItemPlaybackStalledNotification
                                     object:_playerItem];
#endif
            
            
            // add video output
            _videoOutput = [[AVPlayerItemHapDXTOutput alloc] init];
            [_playerItem addOutput:_videoOutput];
            
            
            // create new player
            _player = [[AVPlayer playerWithPlayerItem:_playerItem] retain];
            [_player addObserver:self
                          forKeyPath:kRateKey
                             options:NSKeyValueObservingOptionNew
                             context:&PlayerRateContext];
            
            // loaded
            bLoaded = true;
            
            bSuccess = YES;
            
            if(bAsync == NO){
                dispatch_semaphore_signal(sema);
            }
            
            [asyncLock unlock];
                
            }
            
        }];
    });
    
    // Wait for the dispatch semaphore signal
    if(bAsync == NO){
        dispatch_semaphore_wait(sema, DISPATCH_TIME_FOREVER);
        dispatch_release(sema);
        return bSuccess;
    } else {
        dispatch_release(sema);
        return YES;
    }
        
    }
}


#pragma mark - unload video
- (void)unloadVideoAsync {
    
    bIsUnloaded = YES;
    bReady = NO;
    bLoaded = NO;
    //	bPlayStateBeforeLoad = NO;
    bUpdateFirstFrame = YES;
    bNewFrame = NO;
    bPlaying = NO;
    bFinished = NO;

    [_player pause];
    
    // a reference to all the variables for the block
    __block AVAsset* currentAsset = _asset;
    __block AVPlayerItem* currentItem = _playerItem;
    __block AVPlayer* currentPlayer = _player;
    
    __block AVAssetTrack* currentHapTrack = _hapTrack;
    
    __block AVPlayerItemHapDXTOutput* currentVideoOutput = _videoOutput;
    
    __block HapDecoderFrame* currentHapFrame = _currentFrame;
    
    
    // set all to nil
    // cleanup happens in the block
    _asset = nil;
    _videoOutput = nil;
    _playerItem = nil;
    _player = nil;
    _hapTrack = nil;
    timeObserver = nil;
    _currentFrame = nil;
    
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        
        @autoreleasepool {
            
            [asyncLock lock];
    
            if (currentHapFrame != nil){
                [currentHapFrame autorelease];
                currentHapFrame = nil;
            }
            
            // release asset
            if (currentAsset != nil) {
                [currentAsset cancelLoading];
                [currentAsset autorelease];
                currentAsset = nil;
            }
            
            
            // release current player item
            if(currentItem != nil) {
                
                [currentItem cancelPendingSeeks];
                [currentItem removeObserver:self forKeyPath:kStatusKey context:&ItemStatusContext];
                
                NSNotificationCenter* notificationCenter = [NSNotificationCenter defaultCenter];
                [notificationCenter removeObserver:self
                                              name:AVPlayerItemDidPlayToEndTimeNotification
                                            object:currentItem];
                
                //AVPlayerItemPlaybackStalledNotification only exists from OS X 10.9 or iOS 6.0 and up
#if (__MAC_OS_X_VERSION_MIN_REQUIRED >= 1090) || (__IPHONE_OS_VERSION_MIN_REQUIRED >= 60000)
                [notificationCenter removeObserver:self
                                              name:AVPlayerItemPlaybackStalledNotification
                                            object:currentItem];
#endif
                
                // remove output
                [currentItem removeOutput:currentVideoOutput];
                
                // release videouOutput
                if (currentVideoOutput != nil) {
                    [currentVideoOutput autorelease];
                    currentVideoOutput = nil;
                }
                
                if (currentHapTrack != nil){
                    [currentHapTrack autorelease];
                    currentHapTrack = nil;
                }

                
                [currentPlayer replaceCurrentItemWithPlayerItem:nil];
                
                [currentItem autorelease];
                currentItem = nil;
            }
            
            
            // destroy current player
            if (currentPlayer != nil) {
                [currentPlayer removeObserver:self forKeyPath:kRateKey context:&PlayerRateContext];
                
                [currentPlayer release];
                currentPlayer = nil;
            }
            
            //NSLog(@"item: %lu", (unsigned long)[currentItem retainCount]);
            
            [asyncLock unlock];
            
            if (deallocCond != nil) {
                [deallocCond lock];
                [deallocCond signal];
                [deallocCond unlock];
            }
        }
    });
    
}

- (void)unloadVideo
{
    // create a condition
    deallocCond = [[NSCondition alloc] init];
    [deallocCond lock];
    
    // unload current video
    [self unloadVideoAsync];
    
    // wait for unloadVideoAsync to finish
    [deallocCond wait];
    [deallocCond unlock];
    
    [deallocCond release];
    deallocCond = nil;
}

- (void)close
{
    [asyncLock lock];
    [self unloadVideoAsync];
    [asyncLock unlock];
}




//---------------------------------------------------------- player callbacks.
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    
    if(context == &ItemStatusContext) {
        
        if (object == _playerItem) {
            
            if ([_playerItem status] == AVPlayerItemStatusReadyToPlay) {
                
                if (bReady) {
                    return;
                }
                
                bReady = true;
                
                if(bAutoPlayOnLoad || bPlayStateBeforeLoad) {
                    [self play];
                }
                
                [self update]; // update as soon is ready so pixels are loaded.
                
                
            } else if ([_playerItem status] == AVPlayerItemStatusUnknown) {
                NSLog(@"AVPlayerItemStatusUnknown");
            } else if ([_playerItem status] == AVPlayerItemStatusFailed) {
                NSLog(@"AVPlayerItemStatusFailed");
            } else {
                NSLog(@"AVPlayerItem: such status: %ld", (long)[_playerItem status]);
            }
            
        } else {
            // ignore other objects
        }
        
        return;
    } else if (context == &PlayerRateContext) {
        
        if (object == _player) {
            
            if (bReady &&
                [keyPath isEqualToString:kRateKey])
            {
                float rate = [[change objectForKey:@"new"] floatValue];
                bPlaying = (rate != 0);
            }
        } else {
            // ignore other object
        }
        
        return;
    }
    
    // push it up the observer chain
    [super observeValueForKeyPath:keyPath
                         ofObject:object
                           change:change
                          context:context];
}

- (void)playerItemDidReachEnd {
    
    bFinished = YES;
    bPlaying = NO;
    
    if (speed > 0.0) {
        // playing forward
        if (loop == HapInAVFoundationPlayerLoopType_Normal) {
            [self seekToStart];
            [self play];
        } else if (loop == HapInAVFoundationPlayerLoopType_Palindrome) {
            [self setSpeed:-speed];
            [self play];
        }
        
    } else if (speed < 0.0) {
        // playing backwards
        if (loop == HapInAVFoundationPlayerLoopType_Normal) {
            [self seekToEnd];
            [self play];
        } else if (loop == HapInAVFoundationPlayerLoopType_Palindrome) {
            [self setSpeed:-speed];
            [self play];
        }
    }
    
    
    if(loop != HapInAVFoundationPlayerLoopType_None) {
        bFinished = NO;
    }
}


- (void)playerItemDidStall {
    NSLog(@"playerItem did stall - samples did not arrive in time");
}


//---------------------------------------------------------- update.
- (void)update {
    
    /**
     *  return if,
     *  video is not yet loaded,
     *  video is finished playing.
     */
    if(!bReady || bFinished) {
        bNewFrame = NO;
        return;
    }
    

        // playing paused or playing backwards
        // get samples from videooutput
        [self updateFromVideoOutput];

}


- (void)updateFromVideoOutput {
    
    // get time from player
    CMTime time = [_player currentTime];
    
    HapDecoderFrame *newFrame = [_videoOutput allocFrameClosestToTime:time];
    
    if (newFrame != nil && ![newFrame isEqual:_currentFrame]) {
        
        bNewFrame = YES;
        
        if (_currentFrame){
            [_currentFrame release];
            _currentFrame = nil;
        }
        
        _currentFrame = newFrame;
        
        
    } else {
        // no new frame for time
        bNewFrame = NO;
    }
    
}


//---------------------------------------------------------- play / pause.
- (void)play {
    if([self isReady]) {
        if(![self isPlaying]) {
            [self togglePlayPause];
        }
    } else {
        bPlayStateBeforeLoad = YES;
    }
}

- (void)pause {
    if([self isReady]) {
        if([self isPlaying]) {
            [self togglePlayPause];
        }
    } else {
        bPlayStateBeforeLoad = NO;
    }
}

- (void)togglePlayPause {
    bPlaying = !bPlaying;
    if([self isPlaying]) {
        if([self isFinished]) {
            [self seekToStart];
            bFinished = NO;
        }
        [_player setRate:speed];
    } else {
        [_player pause];
    }
}

- (void)stepByCount:(long)frames
{
    if(![self isReady]) {
        return;
    }
    
    [_playerItem stepByCount:frames];

}

//---------------------------------------------------------- seek.
- (void)seekToStart {
    [self seekToTime:kCMTimeZero withTolerance:kCMTimeZero];
}

- (void)seekToEnd {
    [self seekToTime:[self getDuration] withTolerance:kCMTimeZero];
}

- (void)seekToTime:(CMTime)time {
    [self seekToTime:time withTolerance:kCMTimePositiveInfinity];
}

- (void)seekToTime:(CMTime)time
     withTolerance:(CMTime)tolerance {
    
    if(![self isReady]) {
        return;
    }
    
    if([self isFinished]) {
        bFinished = NO;
    }
    
    // restrict time
    time = CMTimeMaximum(time, kCMTimeZero);
    time = CMTimeMinimum(time, [self getDuration]);
    
    
    // set reader to real requested time
    [_player seekToTime:time
        toleranceBefore:tolerance
         toleranceAfter:tolerance
      completionHandler:^(BOOL finished) {
          
      }];
}

//---------------------------------------------------------- states.
- (BOOL)isReady {
    return bReady;
}

- (BOOL)isLoaded {
    return bLoaded;
}

- (BOOL)isPlaying {
    return bPlaying;
}

- (BOOL)isNewFrame {
    return bNewFrame;
}

- (BOOL)isFinished {
    return bFinished;
}


//---------------------------------------------------------- getters / setters.
- (NSInteger)getWidth {
    
    if (_hapTrack == nil) return 0;
    return [_hapTrack naturalSize].width;
    
}

- (NSInteger)getHeight {
    
    if (_hapTrack == nil) return 0;
    return [_hapTrack naturalSize].height;
    
}

- (CMTime)getCurrentTime {
    
    if (_player == nil) return kCMTimeZero;
    return [_player currentTime];
    
}

- (double)getCurrentTimeInSec {
    return CMTimeGetSeconds([self getCurrentTime]);
}

- (CMTime)getDuration {
    
    if (_asset == nil) return kCMTimeZero;
    return [_asset duration];
    
}

- (double)getDurationInSec {
    return CMTimeGetSeconds([self getDuration]);
}

- (float)getFrameRate {
    
    if (_hapTrack == nil) return 0;
    return [_hapTrack nominalFrameRate];
    
}

- (int)getDurationInFrames {
    return [self getDurationInSec] * [self getFrameRate];
}

- (int)getCurrentFrameNum {
    return [self getCurrentTimeInSec] * [self getFrameRate];
}

- (void)setPosition:(float)position {
    if ([self isReady]) {
        double time = [self getDurationInSec] * position;
        [self seekToTime:CMTimeMakeWithSeconds(time, NSEC_PER_SEC)];
    }
}

- (void)setFrame:(int)frame {
    if ([self isReady]) {
        float position = frame / (float)[self getDurationInFrames];
        [self setPosition:position];
    }
}

- (float)getPosition {
    return ([self getCurrentTimeInSec] / [self getDurationInSec]);
}


- (void)setLoop:(HapInAVFoundationPlayerLoopType)value {
    loop = value;
}

- (HapInAVFoundationPlayerLoopType)getLoop {
    return loop;
}

- (void)setSpeed:(float)value {
    
    if(![self isReady]) {
        return;
    }
    
    if (!_playerItem.canPlayReverse) {
        NSLog(@"ERROR: can not play backwards: not supported (check your codec)");
        value = 0.0;
    }
    if (_videoOutput == nil) {
        NSLog(@"ERROR: can not play backwards: no video output");
        value = 0.0;
    }
    
    speed = value;
    [_player setRate:value];
}

- (float)getSpeed {
    return speed;
}

- (void)setAutoplay:(BOOL)value {
    bAutoPlayOnLoad = value;
}

- (BOOL)getAutoplay {
    return bAutoPlayOnLoad;
}

@end