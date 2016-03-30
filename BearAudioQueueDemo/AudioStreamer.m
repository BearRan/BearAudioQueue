//
//  AudioStreamer.m
//  BearAudioQueueDemo
//
//  Created by Bear on 15/11/5.
//  Copyright © 2015年 Bear. All rights reserved.
//


#import "AudioStreamer.h"
#if TARGET_OS_IPHONE
#import <CFNetwork/CFNetwork.h>
#endif

#define BitRateEstimationMaxPackets 5000
#define BitRateEstimationMinPackets 50

NSString * const ASStatusChangedNotification = @"ASStatusChangedNotification";

NSString * const AS_NO_ERROR_STRING = @"No error.";
NSString * const AS_FILE_STREAM_GET_PROPERTY_FAILED_STRING = @"File stream get property failed.";
NSString * const AS_FILE_STREAM_SEEK_FAILED_STRING = @"File stream seek failed.";
NSString * const AS_FILE_STREAM_PARSE_BYTES_FAILED_STRING = @"Parse bytes failed.";
NSString * const AS_FILE_STREAM_OPEN_FAILED_STRING = @"Open audio file stream failed.";
NSString * const AS_FILE_STREAM_CLOSE_FAILED_STRING = @"Close audio file stream failed.";
NSString * const AS_AUDIO_QUEUE_CREATION_FAILED_STRING = @"Audio queue creation failed.";
NSString * const AS_AUDIO_QUEUE_BUFFER_ALLOCATION_FAILED_STRING = @"Audio buffer allocation failed.";
NSString * const AS_AUDIO_QUEUE_ENQUEUE_FAILED_STRING = @"Queueing of audio buffer failed.";
NSString * const AS_AUDIO_QUEUE_ADD_LISTENER_FAILED_STRING = @"Audio queue add listener failed.";
NSString * const AS_AUDIO_QUEUE_REMOVE_LISTENER_FAILED_STRING = @"Audio queue remove listener failed.";
NSString * const AS_AUDIO_QUEUE_START_FAILED_STRING = @"Audio queue start failed.";
NSString * const AS_AUDIO_QUEUE_BUFFER_MISMATCH_STRING = @"Audio queue buffers don't match.";
NSString * const AS_AUDIO_QUEUE_DISPOSE_FAILED_STRING = @"Audio queue dispose failed.";
NSString * const AS_AUDIO_QUEUE_PAUSE_FAILED_STRING = @"Audio queue pause failed.";
NSString * const AS_AUDIO_QUEUE_STOP_FAILED_STRING = @"Audio queue stop failed.";
NSString * const AS_AUDIO_DATA_NOT_FOUND_STRING = @"No audio data found.";
NSString * const AS_AUDIO_QUEUE_FLUSH_FAILED_STRING = @"Audio queue flush failed.";
NSString * const AS_GET_AUDIO_TIME_FAILED_STRING = @"Audio queue get current time failed.";
NSString * const AS_AUDIO_STREAMER_FAILED_STRING = @"Audio playback failed";
NSString * const AS_NETWORK_CONNECTION_FAILED_STRING = @"Network connection failed";
NSString * const AS_AUDIO_BUFFER_TOO_SMALL_STRING = @"Audio packets are larger than kAQDefaultBufSize.";

@interface AudioStreamer ()

@property (readwrite) AudioStreamerState state;

- (void)handlePropertyChangeForFileStream:(AudioFileStreamID)inAudioFileStream
                     fileStreamPropertyID:(AudioFileStreamPropertyID)inPropertyID
                                  ioFlags:(UInt32 *)ioFlags;

- (void)handleAudioPackets:(const void *)inInputData
               numberBytes:(UInt32)inNumberBytes
             numberPackets:(UInt32)inNumberPackets
        packetDescriptions:(AudioStreamPacketDescription *)inPacketDescriptions;

- (void)handleBufferCompleteForQueue:(AudioQueueRef)inAQ
                              buffer:(AudioQueueBufferRef)inBuffer;

- (void)handlePropertyChangeForQueue:(AudioQueueRef)inAQ
                          propertyID:(AudioQueuePropertyID)inID;

- (void)handleInterruptionChangeToState:(AudioQueuePropertyID)inInterruptionState;

- (void)internalSeekToTime:(double)newSeekTime;
- (void)enqueueBuffer;
- (void)handleReadFromStream:(CFReadStreamRef)aStream eventType:(CFStreamEventType)eventType;

@end




#pragma mark Audio Callback Function Prototypes

void MyAudioQueueOutputCallback(void* inClientData, AudioQueueRef inAQ, AudioQueueBufferRef inBuffer);
void MyAudioQueueIsRunningCallback(void *inUserData, AudioQueueRef inAQ, AudioQueuePropertyID inID);
void MyPropertyListenerProc(	void *							inClientData,
                            AudioFileStreamID				inAudioFileStream,
                            AudioFileStreamPropertyID		inPropertyID,
                            UInt32 *						ioFlags);
void MyPacketsProc(				void *							inClientData,
                   UInt32							inNumberBytes,
                   UInt32							inNumberPackets,
                   const void *					inInputData,
                   AudioStreamPacketDescription	*inPacketDescriptions);
OSStatus MyEnqueueBuffer(AudioStreamer* myData);

void MyAudioSessionInterruptionListener(void *inClientData, UInt32 inInterruptionState);

#pragma mark Audio Callback Function Implementations

//
// MyPropertyListenerProc
//
// Receives notification when the AudioFileStream has audio packets to be
// played. In response, this function creates the AudioQueue, getting it
// ready to begin playback (playback won't begin until audio packets are
// sent to the queue in MyEnqueueBuffer).
//
// This function is adapted from Apple's example in AudioFileStreamExample with
// kAudioQueueProperty_IsRunning listening added.
//
void MyPropertyListenerProc(	void *							inClientData,
                            AudioFileStreamID				inAudioFileStream,
                            AudioFileStreamPropertyID		inPropertyID,
                            UInt32 *						ioFlags)
{
    // this is called by audio file stream when it finds property values
    AudioStreamer* streamer = (__bridge AudioStreamer *)inClientData;
    [streamer
     handlePropertyChangeForFileStream:inAudioFileStream
     fileStreamPropertyID:inPropertyID
     ioFlags:ioFlags];
}

//
// MyPacketsProc
//
// When the AudioStream has packets to be played, this function gets an
// idle audio buffer and copies the audio packets into it. The calls to
// MyEnqueueBuffer won't return until there are buffers available (or the
// playback has been stopped).
//
// This function is adapted from Apple's example in AudioFileStreamExample with
// CBR functionality added.
//
void MyPacketsProc(				void *							inClientData,
                   UInt32							inNumberBytes,
                   UInt32							inNumberPackets,
                   const void *					inInputData,
                   AudioStreamPacketDescription	*inPacketDescriptions)
{
    // this is called by audio file stream when it finds packets of audio
    AudioStreamer* streamer = (__bridge AudioStreamer *)inClientData;
    [streamer
     handleAudioPackets:inInputData
     numberBytes:inNumberBytes
     numberPackets:inNumberPackets
     packetDescriptions:inPacketDescriptions];
}

//
// MyAudioQueueOutputCallback
//
// Called from the AudioQueue when playback of specific buffers completes. This
// function signals from the AudioQueue thread to the AudioStream thread that
// the buffer is idle and available for copying data.
//
// This function is unchanged from Apple's example in AudioFileStreamExample.
//
void MyAudioQueueOutputCallback(	void*					inClientData,
                                AudioQueueRef			inAQ,
                                AudioQueueBufferRef		inBuffer)
{
    // this is called by the audio queue when it has finished decoding our data.
    // The buffer is now free to be reused.
    AudioStreamer* streamer = (__bridge AudioStreamer*)inClientData;
    [streamer handleBufferCompleteForQueue:inAQ buffer:inBuffer];
}

//
// MyAudioQueueIsRunningCallback
//
// Called from the AudioQueue when playback is started or stopped. This
// information is used to toggle the observable "isPlaying" property and
// set the "finished" flag.
//
void MyAudioQueueIsRunningCallback(void *inUserData, AudioQueueRef inAQ, AudioQueuePropertyID inID)
{
    AudioStreamer* streamer = (__bridge AudioStreamer *)inUserData;
    [streamer handlePropertyChangeForQueue:inAQ propertyID:inID];
}


//  AudioSession中断监听
//  中断事件之后会执行回调（比如中途有来电）
void MyAudioSessionInterruptionListener(void *inClientData, UInt32 inInterruptionState)
{
    AudioStreamer* streamer = (__bridge AudioStreamer *)inClientData;
    [streamer handleInterruptionChangeToState:inInterruptionState];
}

#pragma mark CFReadStream Callback Function Implementations


//  读取流数据的回调函数
//  当发生错误或者有数据可读时会调用
void ASReadStreamCallBack
(
 CFReadStreamRef aStream,
 CFStreamEventType eventType,
 void* inClientInfo
 )
{
    AudioStreamer* streamer = (__bridge AudioStreamer *)inClientInfo;
    [streamer handleReadFromStream:aStream eventType:eventType];
}




@implementation AudioStreamer

@synthesize errorCode;
@synthesize state;
@synthesize bitRate;
@synthesize httpHeaders;


- (id)initWithURL:(NSURL *)aURL
{
    self = [super init];
    if (self != nil)
    {
        url = aURL;
    }
    
    return self;
}

- (void)dealloc
{
    [self stop];
}

- (BOOL)isFinishing
{
    @synchronized (self)
    {
        if ((errorCode != AS_NO_ERROR && state != AS_INITIALIZED) ||
            ((state == AS_STOPPING || state == AS_STOPPED) &&
             stopReason != AS_STOPPING_TEMPORARILY))
        {
            return YES;
        }
    }
    
    return NO;
}

- (BOOL)isPlaying
{
    if (state == AS_PLAYING)
    {
        return YES;
    }
    
    return NO;
}

- (BOOL)isPaused
{
    if (state == AS_PAUSED)
    {
        return YES;
    }
    
    return NO;
}

- (BOOL)isWaiting
{
    @synchronized(self)
    {
        if (state == AS_STARTING_FILE_THREAD ||
            state == AS_WAITING_FOR_DATA ||
            state == AS_WAITING_FOR_QUEUE_TO_START ||
            state == AS_BUFFERING)
        {
            return YES;
        }
    }
    
    return NO;
}

- (BOOL)isIdle
{
    // 播放完毕, 空闲状态
    if (state == AS_INITIALIZED)
    {
        return YES;
    }
    
    return NO;
}


//
// runLoopShouldExit
//
// returns YES if the run loop should exit.
//
- (BOOL)runLoopShouldExit
{
    @synchronized(self)
    {
        // 存在错误码,或非临时性的播放停止时, 需要终止streamer
        if ( errorCode != AS_NO_ERROR ||
            (state == AS_STOPPED && stopReason != AS_STOPPING_TEMPORARILY)
            )
        {
            return YES;
        }
    }
    
    return NO;
}


+ (NSString *)stringForErrorCode:(AudioStreamerErrorCode)anErrorCode
{
    switch (anErrorCode)
    {
        case AS_NO_ERROR:
            return AS_NO_ERROR_STRING;
        case AS_FILE_STREAM_GET_PROPERTY_FAILED:
            return AS_FILE_STREAM_GET_PROPERTY_FAILED_STRING;
        case AS_FILE_STREAM_SEEK_FAILED:
            return AS_FILE_STREAM_SEEK_FAILED_STRING;
        case AS_FILE_STREAM_PARSE_BYTES_FAILED:
            return AS_FILE_STREAM_PARSE_BYTES_FAILED_STRING;
        case AS_AUDIO_QUEUE_CREATION_FAILED:
            return AS_AUDIO_QUEUE_CREATION_FAILED_STRING;
        case AS_AUDIO_QUEUE_BUFFER_ALLOCATION_FAILED:
            return AS_AUDIO_QUEUE_BUFFER_ALLOCATION_FAILED_STRING;
        case AS_AUDIO_QUEUE_ENQUEUE_FAILED:
            return AS_AUDIO_QUEUE_ENQUEUE_FAILED_STRING;
        case AS_AUDIO_QUEUE_ADD_LISTENER_FAILED:
            return AS_AUDIO_QUEUE_ADD_LISTENER_FAILED_STRING;
        case AS_AUDIO_QUEUE_REMOVE_LISTENER_FAILED:
            return AS_AUDIO_QUEUE_REMOVE_LISTENER_FAILED_STRING;
        case AS_AUDIO_QUEUE_START_FAILED:
            return AS_AUDIO_QUEUE_START_FAILED_STRING;
        case AS_AUDIO_QUEUE_BUFFER_MISMATCH:
            return AS_AUDIO_QUEUE_BUFFER_MISMATCH_STRING;
        case AS_FILE_STREAM_OPEN_FAILED:
            return AS_FILE_STREAM_OPEN_FAILED_STRING;
        case AS_FILE_STREAM_CLOSE_FAILED:
            return AS_FILE_STREAM_CLOSE_FAILED_STRING;
        case AS_AUDIO_QUEUE_DISPOSE_FAILED:
            return AS_AUDIO_QUEUE_DISPOSE_FAILED_STRING;
        case AS_AUDIO_QUEUE_PAUSE_FAILED:
            return AS_AUDIO_QUEUE_DISPOSE_FAILED_STRING;
        case AS_AUDIO_QUEUE_FLUSH_FAILED:
            return AS_AUDIO_QUEUE_FLUSH_FAILED_STRING;
        case AS_AUDIO_DATA_NOT_FOUND:
            return AS_AUDIO_DATA_NOT_FOUND_STRING;
        case AS_GET_AUDIO_TIME_FAILED:
            return AS_GET_AUDIO_TIME_FAILED_STRING;
        case AS_NETWORK_CONNECTION_FAILED:
            return AS_NETWORK_CONNECTION_FAILED_STRING;
        case AS_AUDIO_QUEUE_STOP_FAILED:
            return AS_AUDIO_QUEUE_STOP_FAILED_STRING;
        case AS_AUDIO_STREAMER_FAILED:
            return AS_AUDIO_STREAMER_FAILED_STRING;
        case AS_AUDIO_BUFFER_TOO_SMALL:
            return AS_AUDIO_BUFFER_TOO_SMALL_STRING;
        default:
            return AS_AUDIO_STREAMER_FAILED_STRING;
    }
    
    return AS_AUDIO_STREAMER_FAILED_STRING;
}


//  执行错误时的方法
- (void)failWithErrorCode:(AudioStreamerErrorCode)anErrorCode
{
    @synchronized(self)
    {
        if (errorCode != AS_NO_ERROR)
        {
            return;
        }
        
        errorCode = anErrorCode;
        
        if (err)
        {
            char *errChars = (char *)&err;
            if (![self isFinishing]) {
                NSLog(@"%@ err: %c%c%c%c %d\n",
                      [AudioStreamer stringForErrorCode:anErrorCode],
                      errChars[3], errChars[2], errChars[1], errChars[0],
                      (int)err);
            }
        }
        else
        {
            NSLog(@"%@", [AudioStreamer stringForErrorCode:anErrorCode]);
        }
        
        if (state == AS_PLAYING ||
            state == AS_PAUSED ||
            state == AS_BUFFERING)
        {
            self.state = AS_STOPPING;
            stopReason = AS_STOPPING_ERROR;
            AudioQueueStop(audioQueue, true);
        }
        
        if (![self isFinishing]) {
            NSLog(@"网络出现故障,请重试一次.");
        }
    }
}

//
// mainThreadStateNotification
//
// Method invoked on main thread to send notifications to the main thread's
// notification center.
//
- (void)mainThreadStateNotification
{
    NSNotification *notification = [NSNotification notificationWithName:ASStatusChangedNotification object:self];
    [[NSNotificationCenter defaultCenter] postNotification:notification];
}



#pragma mark 重写state方法
- (void)setState:(AudioStreamerState)aStatus
{
    @synchronized(self)
    {
        if (state != aStatus)
        {
            state = aStatus;
            
            //在主线程post ASStatus状态的通知
            if ([[NSThread currentThread] isEqual:[NSThread mainThread]])
            {
                [self mainThreadStateNotification];
            }
            //强制切换到主线程post ASStatus状态的通知
            else
            {
                [self performSelectorOnMainThread:@selector(mainThreadStateNotification)
                 withObject:nil waitUntilDone:NO];
            }
        }
    }
}


#pragma mark 判断文件类型
+ (AudioFileTypeID)hintForFileExtension:(NSString *)fileExtension
{
    AudioFileTypeID fileTypeHint = kAudioFileAAC_ADTSType;
    if ([fileExtension isEqual:@"mp3"])
    {
        fileTypeHint = kAudioFileMP3Type;
    }
    else if ([fileExtension isEqual:@"wav"])
    {
        fileTypeHint = kAudioFileWAVEType;
    }
    else if ([fileExtension isEqual:@"aifc"])
    {
        fileTypeHint = kAudioFileAIFCType;
    }
    else if ([fileExtension isEqual:@"aiff"])
    {
        fileTypeHint = kAudioFileAIFFType;
    }
    else if ([fileExtension isEqual:@"m4a"])
    {
        fileTypeHint = kAudioFileM4AType;
    }
    else if ([fileExtension isEqual:@"mp4"])
    {
        fileTypeHint = kAudioFileMPEG4Type;
    }
    else if ([fileExtension isEqual:@"caf"])
    {
        fileTypeHint = kAudioFileCAFType;
    }
    else if ([fileExtension isEqual:@"aac"])
    {
        fileTypeHint = kAudioFileAAC_ADTSType;
    }
    return fileTypeHint;
}


//  打开读取文件流
//  通过对指定的URL请求
- (BOOL)openReadStream
{
    @synchronized(self)
    {
        NSAssert([[NSThread currentThread] isEqual:internalThread],
                 @"File stream download must be started on the internalThread");
        NSAssert(stream == nil, @"下载的文件流已经初始化");
        
        //  创建HTTP GET请求
        CFHTTPMessageRef message= CFHTTPMessageCreateRequest(NULL, (CFStringRef)@"GET", (__bridge CFURLRef)url, kCFHTTPVersion1_1);
        
        //  设定头文件
        if (fileLength > 0 && seekByteOffset > 0)
        {
            CFHTTPMessageSetHeaderFieldValue(message, CFSTR("Range"),
                                             (__bridge CFStringRef)[NSString stringWithFormat:@"bytes=%ld-%ld", seekByteOffset, fileLength]);
            discontinuous = YES;
        }
        
        //  创建读取流
        stream = CFReadStreamCreateForHTTPRequest(NULL, message);
        CFRelease(message);
        
        //  允许重定向
        if (CFReadStreamSetProperty(
                                    stream,
                                    kCFStreamPropertyHTTPShouldAutoredirect,
                                    kCFBooleanTrue) == false)
        {
            NSLog(@"无法读取数据流");
            return NO;
        }
        
        //  读取数据流设定属性
        CFDictionaryRef proxySettings = CFNetworkCopySystemProxySettings();
        CFReadStreamSetProperty(stream, kCFStreamPropertyHTTPProxy, proxySettings);
        CFRelease(proxySettings);
        
        //  SSL链接的处理
        if( [[url absoluteString] rangeOfString:@"https"].location != NSNotFound )
        {
            NSDictionary *sslSettings =
            [NSDictionary dictionaryWithObjectsAndKeys:
             (NSString *)kCFStreamSocketSecurityLevelNegotiatedSSL, kCFStreamSSLLevel,
             [NSNumber numberWithBool:YES], kCFStreamSSLAllowsExpiredCertificates,
             [NSNumber numberWithBool:YES], kCFStreamSSLAllowsExpiredRoots,
             [NSNumber numberWithBool:YES], kCFStreamSSLAllowsAnyRoot,
             [NSNumber numberWithBool:NO], kCFStreamSSLValidatesCertificateChain,
             [NSNull null], kCFStreamSSLPeerName,
             nil];
            
            CFReadStreamSetProperty(stream, kCFStreamPropertySSLSettings, (__bridge CFTypeRef)(sslSettings));
        }
        
        //  准备接收数据
        self.state = AS_WAITING_FOR_DATA;
        
        //  打开数据流
        if (!CFReadStreamOpen(stream))
        {
            CFRelease(stream);
            NSLog(@"无法读取数据流");
            return NO;
        }
        
        //  设置回调方法来接收数据,在流被打开、有数据可以读取等事件发生时调用回调函数
        CFStreamClientContext context = {0, (__bridge void *)(self), NULL, NULL, NULL};
        CFReadStreamSetClient(
                              stream,
                              kCFStreamEventHasBytesAvailable | kCFStreamEventErrorOccurred | kCFStreamEventEndEncountered,
                              ASReadStreamCallBack,
                              &context);
        CFReadStreamScheduleWithRunLoop(stream, CFRunLoopGetCurrent(), kCFRunLoopCommonModes);
    }
    
    return YES;
}

//
// startInternal
//
// This is the start method for the AudioStream thread. This thread is created
// because it will be blocked when there are no audio buffers idle (and ready
// to receive audio data).
//
// Activity in this thread:
//	- Creation and cleanup of all AudioFileStream and AudioQueue objects
//	- Receives data from the CFReadStream
//	- AudioFileStream processing
//	- Copying of data from AudioFileStream into audio buffers
//  - Stopping of the thread because of end-of-file
//	- Stopping due to error or failure
//
// Activity *not* in this thread:
//	- AudioQueue playback and notifications (happens in AudioQueue thread)
//  - Actual download of NSURLConnection data (NSURLConnection's thread)
//	- Creation of the AudioStreamer (other, likely "main" thread)
//	- Invocation of -start method (other, likely "main" thread)
//	- User/manual invocation of -stop (other, likely "main" thread)
//
// This method contains bits of the "main" function from Apple's example in
// AudioFileStreamExample.
//
- (void)startInternal
{
    @synchronized(self)
    {
        if (state != AS_STARTING_FILE_THREAD)
        {
            if (state != AS_STOPPING &&
                state != AS_STOPPED)
            {
                NSLog(@"暂未开始播放. 状态码为: %d", state);
            }
            self.state = AS_INITIALIZED;
            
            return;
        }
        
        //  设置AudioSession的种类，
        AudioSessionInitialize (
                                NULL,
                                NULL,
                                MyAudioSessionInterruptionListener, //中断监听
                                (__bridge void *)(self)             //回调时附带的对象
                                );
        
        //  设置类别，执行播放功能
        UInt32 sessionCategory = kAudioSessionCategory_MediaPlayback;
        AudioSessionSetProperty (
                                 kAudioSessionProperty_AudioCategory,
                                 sizeof (sessionCategory),
                                 &sessionCategory
                                 );
        //  启动AudioSession
        AudioSessionSetActive(true);
        
        //  互斥锁初始化
        pthread_mutex_init(&queueBuffersMutex, NULL);
        pthread_cond_init(&queueBufferReadyCondition, NULL);
        
        if (![self openReadStream])
        {
            //  否则跳转到清空步骤
            goto cleanup;
        }
    }
    
    //  一直运行，直到播放结束或者中途播放失败
    BOOL isRunning = YES;
    do
    {
        isRunning = [[NSRunLoop currentRunLoop]
                     runMode:NSDefaultRunLoopMode
                     beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.25]];
        
        @synchronized(self) {
            if (seekWasRequested) {
                [self internalSeekToTime:requestedSeekTime];
                seekWasRequested = NO;
            }
        }
        
        //  如果列队中没有Buffer，需要在此处进行检测。无需改变状态（可能由于没有进入到同步进程导致）
        if (buffersUsed == 0 && self.state == AS_PLAYING)
        {
            err = AudioQueuePause(audioQueue);
            if (err)
            {
                [self failWithErrorCode:AS_AUDIO_QUEUE_PAUSE_FAILED];
                return;
            }
            
            //  网络不好自动缓冲
            self.state = AS_BUFFERING;
        }
    } while (isRunning && ![self runLoopShouldExit]);
    
cleanup:
    
    @synchronized(self)
    {
        //  如果stream仍然存在则清空
        if (stream)
        {
            CFReadStreamClose(stream);
            CFRelease(stream);
            stream = nil;
        }
        
        //  关闭AudioFile
        if (audioFileStream)
        {
            err = AudioFileStreamClose(audioFileStream);
            audioFileStream = nil;
            if (err)
            {
                [self failWithErrorCode:AS_FILE_STREAM_CLOSE_FAILED];
            }
        }
        
        //  处理AudioQueue
        if (audioQueue)
        {
            err = AudioQueueDispose(audioQueue, true);
            audioQueue = nil;
            if (err)
            {
                [self failWithErrorCode:AS_AUDIO_QUEUE_DISPOSE_FAILED];
            }
        }
        
        pthread_mutex_destroy(&queueBuffersMutex);
        pthread_cond_destroy(&queueBufferReadyCondition);
        
        AudioSessionSetActive(false);
        
        httpHeaders = nil;
        
        bytesFilled = 0;
        packetsFilled = 0;
        seekByteOffset = 0;
        packetBufferSize = 0;
        self.state = AS_INITIALIZED;
        
        internalThread = nil;
    }
}


// internalSeekToTime:
//
// Called from our internal runloop to reopen the stream at a seeked location
//
- (void)internalSeekToTime:(double)newSeekTime
{
    if ([self calculatedBitRate] == 0.0 || fileLength <= 0)
    {
        return;
    }
    
    //
    // Calculate the byte offset for seeking
    //
    seekByteOffset = dataOffset +
    (newSeekTime / self.duration) * (fileLength - dataOffset);
    
    //
    // Attempt to leave 1 useful packet at the end of the file (although in
    // reality, this may still seek too far if the file has a long trailer).
    //
    if (seekByteOffset > fileLength - 2 * packetBufferSize)
    {
        seekByteOffset = fileLength - 2 * packetBufferSize;
    }
    
    //
    // Store the old time from the audio queue and the time that we're seeking
    // to so that we'll know the correct time progress after seeking.
    //
    seekTime = newSeekTime;
    
    //
    // Attempt to align the seek with a packet boundary
    //
    double calculatedBitRate = [self calculatedBitRate];
    if (packetDuration > 0 &&
        calculatedBitRate > 0)
    {
        UInt32 ioFlags = 0;
        SInt64 packetAlignedByteOffset;
        SInt64 seekPacket = floor(newSeekTime / packetDuration);
        err = AudioFileStreamSeek(audioFileStream, seekPacket, &packetAlignedByteOffset, &ioFlags);
        if (!err && !(ioFlags & kAudioFileStreamSeekFlag_OffsetIsEstimated))
        {
            seekTime -= ((seekByteOffset - dataOffset) - packetAlignedByteOffset) * 8.0 / calculatedBitRate;
            seekByteOffset = packetAlignedByteOffset + dataOffset;
        }
    }
    
    //
    // Close the current read straem
    //
    if (stream)
    {
        CFReadStreamClose(stream);
        CFRelease(stream);
        stream = nil;
    }
    
    //
    // Stop the audio queue
    //
    self.state = AS_STOPPING;
    stopReason = AS_STOPPING_TEMPORARILY;
    err = AudioQueueStop(audioQueue, true);
    if (err)
    {
        [self failWithErrorCode:AS_AUDIO_QUEUE_STOP_FAILED];
        return;
    }
    
    //
    // Re-open the file stream. It will request a byte-range starting at
    // seekByteOffset.
    //
    [self openReadStream];
}

//
// seekToTime:
//
// Attempts to seek to the new time. Will be ignored if the bitrate or fileLength
// are unknown.
//
// Parameters:
//    newTime - the time to seek to
//
- (void)seekToTime:(double)newSeekTime
{
    @synchronized(self)
    {
        seekWasRequested = YES;
        requestedSeekTime = newSeekTime;
    }
}

//
// progress
//
// returns the current playback progress. Will return zero if sampleRate has
// not yet been detected.
//
- (double)progress
{
    @synchronized(self)
    {
        if (sampleRate > 0/* && ![self isFinishing]*/)
        {
            if (state != AS_PLAYING && state != AS_PAUSED && state != AS_BUFFERING && state != AS_STOPPING)
            {
                return lastProgress;
            }
            
            AudioTimeStamp queueTime;
            Boolean discontinuity;
            err = AudioQueueGetCurrentTime(audioQueue, NULL, &queueTime, &discontinuity);
            
            const OSStatus AudioQueueStopped = 0x73746F70; // 0x73746F70 is 'stop'
            if (err == AudioQueueStopped)
            {
                return lastProgress;
            }
            else if (err)
            {
                [self failWithErrorCode:AS_GET_AUDIO_TIME_FAILED];
            }
            
            double progress = seekTime + queueTime.mSampleTime / sampleRate;
            if (progress < 0.0)
            {
                progress = 0.0;
            }
            
            lastProgress = progress;
            return progress;
        }
    }
    
    return lastProgress;
}

//
// calculatedBitRate
//
// returns the bit rate, if known. Uses packet duration times running bits per
//   packet if available, otherwise it returns the nominal bitrate. Will return
//   zero if no useful option available.
//
- (double)calculatedBitRate
{
    if (packetDuration && processedPacketsCount > BitRateEstimationMinPackets)
    {
        double averagePacketByteSize = processedPacketsSizeTotal / processedPacketsCount;
        return 8.0 * averagePacketByteSize / packetDuration;
    }
    
    if (bitRate)
    {
        return (double)bitRate;
    }
    
    return 0;
}

//
// duration
//
// Calculates the duration of available audio from the bitRate and fileLength.
//
// returns the calculated duration in seconds.
//
- (double)duration
{
    double calculatedBitRate = [self calculatedBitRate];
    
    if (calculatedBitRate == 0 || fileLength == 0)
    {
        return 0.0;
    }
    
    return (fileLength - dataOffset) / (calculatedBitRate * 0.125);
}

- (NSString *)currentTime
{
    NSString *current = [NSString stringWithFormat:@"%d:%02d",
                         (int)[self progress] / 60,
                         (int)[self progress] % 60, nil];
    return  current;
}

- (NSString *)totalTime
{
    NSString *total = [NSString stringWithFormat:@"-%d:%02d",
                       (int)((int)([self duration] - [self progress])) / 60,
                       (int)((int)([self duration] - [self progress])) % 60, nil];
    return total;
}


//  开始
//  在新的线程中运行
- (void)start
{
    //  线程锁，至多只有一个线程可以执行该方法
    @synchronized (self)
    {
        //  暂停
        if (state == AS_PAUSED)
        {
            [self pause];
        }
        
        //  初始化
        else if (state == AS_INITIALIZED)
        {
            //NSAssert调试助手，当下面条件不满足时打印出相关日志
            NSAssert([[NSThread currentThread] isEqual:[NSThread mainThread]], @"只能在主线程中进行播放");
            
            notificationCenter = [NSNotificationCenter defaultCenter];
            self.state = AS_STARTING_FILE_THREAD;
            
            //  在新的线程中执行开始程序
            internalThread = [[NSThread alloc] initWithTarget:self
                                                     selector:@selector(startInternal)
                                                       object:nil];
            [internalThread start];
        }
        
        //  播放
        else if (state == AS_PLAYING)
        {
            
        }
    }
}


//
// pause
//
// A togglable pause function between pause and play
//
- (void)pause
{
    @synchronized(self)
    {
        if (state == AS_PLAYING)
        {
            //AudioQueue暂停
            err = AudioQueuePause(audioQueue);
            if (err)
            {
                [self failWithErrorCode:AS_AUDIO_QUEUE_PAUSE_FAILED];
                return;
            }
            self.state = AS_PAUSED;
        }
        else if (state == AS_PAUSED)
        {
            //AudioQueue播放
            err = AudioQueueStart(audioQueue, NULL);
            if (err)
            {
                [self failWithErrorCode:AS_AUDIO_QUEUE_START_FAILED];
                return;
            }
            self.state = AS_PLAYING;
        }
    }
}

//
// stop
//
// This method can be called to stop downloading/playback before it completes.
// It is automatically called when an error occurs.
//
// If playback has not started before this method is called, it will toggle the
// "isPlaying" property so that it is guaranteed to transition to true and
// back to false
//
- (void)stop
{
    @synchronized(self)
    {
        if (audioQueue &&
            (state == AS_PLAYING || state == AS_PAUSED ||
             state == AS_BUFFERING || state == AS_WAITING_FOR_QUEUE_TO_START))
        {
            self.state = AS_STOPPING;
            stopReason = AS_STOPPING_USER_ACTION;
            err = AudioQueueStop(audioQueue, true);
            if (err)
            {
                [self failWithErrorCode:AS_AUDIO_QUEUE_STOP_FAILED];
                return;
            }
        }
        else if (state != AS_INITIALIZED)
        {
            self.state = AS_STOPPED;
            stopReason = AS_STOPPING_USER_ACTION;
        }
        seekWasRequested = NO;
    }
    
    while (state != AS_INITIALIZED)
    {
        [NSThread sleepForTimeInterval:0.1];
    }
}


//  把文件流读取到AudioFileStream中
- (void)handleReadFromStream:(CFReadStreamRef)aStream eventType:(CFStreamEventType)eventType
{
    if (aStream != stream)
    {
        return;
    }
    
    if (eventType == kCFStreamEventErrorOccurred)
    {
        [self failWithErrorCode:AS_AUDIO_DATA_NOT_FOUND];
    }
    else if (eventType == kCFStreamEventEndEncountered)
    {
        @synchronized(self)
        {
            if ([self isFinishing])
            {
                return;
            }
        }
        
        //  如果有部分的Buffer装填完毕，交给AudioQueue进行处理
        if (bytesFilled)
        {
            if (self.state == AS_WAITING_FOR_DATA)
            {
                //  数据准备完毕
                self.state = AS_FLUSHING_EOF;
            }
            [self enqueueBuffer];
        }
        
        @synchronized(self)
        {
            if (state == AS_WAITING_FOR_DATA)
            {
                [self failWithErrorCode:AS_AUDIO_DATA_NOT_FOUND];
            }
            
            else if (![self isFinishing])
            {
                if (audioQueue)
                {
                    //  在文件流的结尾处处理
                    err = AudioQueueFlush(audioQueue);
                    if (err)
                    {
                        [self failWithErrorCode:AS_AUDIO_QUEUE_FLUSH_FAILED];
                        return;
                    }
                    
                    self.state = AS_STOPPING;
                    stopReason = AS_STOPPING_EOF;
                    err = AudioQueueStop(audioQueue, false);
                    if (err)
                    {
                        [self failWithErrorCode:AS_AUDIO_QUEUE_FLUSH_FAILED];
                        return;
                    }
                }
                else
                {
                    self.state = AS_STOPPED;
                    stopReason = AS_STOPPING_EOF;
                }
            }
        }
    }
    else if (eventType == kCFStreamEventHasBytesAvailable)
    {
        if (!httpHeaders)
        {
            CFTypeRef message =
            CFReadStreamCopyProperty(stream, kCFStreamPropertyHTTPResponseHeader);
            httpHeaders =
            (__bridge NSDictionary *)CFHTTPMessageCopyAllHeaderFields((CFHTTPMessageRef)message);
            CFRelease(message);
            
            //  获取文件长度
            if (seekByteOffset == 0)
            {
                fileLength = [[httpHeaders objectForKey:@"Content-Length"] integerValue];
            }
        }
        
        if (!audioFileStream)
        {
            AudioFileTypeID fileTypeHint =
            [AudioStreamer hintForFileExtension:[[url path] pathExtension]];
            
            err = AudioFileStreamOpen((__bridge void * _Nullable)(self), MyPropertyListenerProc, MyPacketsProc,
                                      fileTypeHint, &audioFileStream);
            if (err)
            {
                [self failWithErrorCode:AS_FILE_STREAM_OPEN_FAILED];
                return;
            }
        }
        
        UInt8 bytes[kAQDefaultBufSize];
        CFIndex length;
        @synchronized(self)
        {
            if ([self isFinishing] || !CFReadStreamHasBytesAvailable(stream))
            {
                return;
            }
            
            //  从字节流中读取字节
            length = CFReadStreamRead(stream, bytes, kAQDefaultBufSize);
            
            if (length == -1)
            {
                [self failWithErrorCode:AS_AUDIO_DATA_NOT_FOUND];
                return;
            }
            
            if (length == 0)
            {
                return;
            }
        }
        
        if (discontinuous)
        {
            err = AudioFileStreamParseBytes(audioFileStream, length, bytes, kAudioFileStreamParseFlag_Discontinuity);
            if (err)
            {
                [self failWithErrorCode:AS_FILE_STREAM_PARSE_BYTES_FAILED];
                return;
            }
        }
        else
        {
            err = AudioFileStreamParseBytes(audioFileStream, length, bytes, 0);
            if (err)
            {
                [self failWithErrorCode:AS_FILE_STREAM_PARSE_BYTES_FAILED];
                return;
            }
        }
    }
}


//  Buffer列队处理
- (void)enqueueBuffer
{
    @synchronized(self)
    {
        if ([self isFinishing] || stream == 0)
        {
            return;
        }
        
        //  设置正在使用的flag
        inuse[fillBufferIndex] = true;
        buffersUsed++;
        
        // 列队的Buffer
        AudioQueueBufferRef fillBuf = audioQueueBuffer[fillBufferIndex];
        fillBuf->mAudioDataByteSize = bytesFilled;
        
        if (packetsFilled)
        {
            err = AudioQueueEnqueueBuffer(audioQueue, fillBuf, packetsFilled, packetDescs);
        }
        else
        {
            err = AudioQueueEnqueueBuffer(audioQueue, fillBuf, 0, NULL);
        }
        
        if (err)
        {
            [self failWithErrorCode:AS_AUDIO_QUEUE_ENQUEUE_FAILED];
            return;
        }
        
        
        if (state == AS_BUFFERING ||
            state == AS_WAITING_FOR_DATA ||
            state == AS_FLUSHING_EOF ||
            (state == AS_STOPPED && stopReason == AS_STOPPING_TEMPORARILY))
        {
            if (state == AS_FLUSHING_EOF || buffersUsed == kNumAQBufs - 1)
            {
                if (self.state == AS_BUFFERING)
                {
                    err = AudioQueueStart(audioQueue, NULL);
                    if (err)
                    {
                        [self failWithErrorCode:AS_AUDIO_QUEUE_START_FAILED];
                        return;
                    }
                    self.state = AS_PLAYING;
                }
                else
                {
                    self.state = AS_WAITING_FOR_QUEUE_TO_START;
                    
                    err = AudioQueueStart(audioQueue, NULL);
                    if (err)
                    {
                        [self failWithErrorCode:AS_AUDIO_QUEUE_START_FAILED];
                        return;
                    }
                }
            }
        }
        
        //  读取下一个buffer
        if (++fillBufferIndex >= kNumAQBufs) fillBufferIndex = 0;
        bytesFilled = 0;
        packetsFilled = 0;
    }
    
    //  一直等待直到最后一个buffer不在被使用的状态中
    pthread_mutex_lock(&queueBuffersMutex);
    while (inuse[fillBufferIndex])
    {
        pthread_cond_wait(&queueBufferReadyCondition, &queueBuffersMutex);
    }
    pthread_mutex_unlock(&queueBuffersMutex);
}

//
// createQueue
//
// Method to create the AudioQueue from the parameters gathered by the
// AudioFileStream.
//
// Creation is deferred to the handling of the first audio packet (although
// it could be handled any time after kAudioFileStreamProperty_ReadyToProducePackets
// is true).
//
//  创建列队
- (void)createQueue
{
    sampleRate = asbd.mSampleRate;
    packetDuration = asbd.mFramesPerPacket / sampleRate;
    
    err = AudioQueueNewOutput(&asbd, MyAudioQueueOutputCallback, (__bridge void * _Nullable)(self), NULL, NULL, 0, &audioQueue);
    if (err)
    {
        [self failWithErrorCode:AS_AUDIO_QUEUE_CREATION_FAILED];
        return;
    }
    
    //  监听isRunning属性
    err = AudioQueueAddPropertyListener(audioQueue, kAudioQueueProperty_IsRunning, MyAudioQueueIsRunningCallback, (__bridge void * _Nullable)(self));
    if (err)
    {
        [self failWithErrorCode:AS_AUDIO_QUEUE_ADD_LISTENER_FAILED];
        return;
    }
    
    //  获取packet大小
    UInt32 sizeOfUInt32 = sizeof(UInt32);
    err = AudioFileStreamGetProperty(audioFileStream, kAudioFileStreamProperty_PacketSizeUpperBound, &sizeOfUInt32, &packetBufferSize);
    if (err || packetBufferSize == 0)
    {
        err = AudioFileStreamGetProperty(audioFileStream, kAudioFileStreamProperty_MaximumPacketSize, &sizeOfUInt32, &packetBufferSize);
        if (err || packetBufferSize == 0)
        {
            //  使用默认size
            packetBufferSize = kAQDefaultBufSize;
        }
    }
    
    //  重新分配QueueBuffer的内存空间
    for (unsigned int i = 0; i < kNumAQBufs; ++i)
    {
        err = AudioQueueAllocateBuffer(audioQueue, packetBufferSize, &audioQueueBuffer[i]);
        if (err)
        {
            [self failWithErrorCode:AS_AUDIO_QUEUE_BUFFER_ALLOCATION_FAILED];
            return;
        }
    }
    
    //  获取cookie的size
    UInt32 cookieSize;
    Boolean writable;
    OSStatus ignorableError;
    ignorableError = AudioFileStreamGetPropertyInfo(audioFileStream, kAudioFileStreamProperty_MagicCookieData, &cookieSize, &writable);
    if (ignorableError)
    {
        return;
    }
    
    //  获取cookie的数据
    void* cookieData = calloc(1, cookieSize);
    ignorableError = AudioFileStreamGetProperty(audioFileStream, kAudioFileStreamProperty_MagicCookieData, &cookieSize, cookieData);
    if (ignorableError)
    {
        return;
    }
    
    //  将cookie放入列队中处理
    ignorableError = AudioQueueSetProperty(audioQueue, kAudioQueueProperty_MagicCookie, cookieData, cookieSize);
    free(cookieData);
    if (ignorableError)
    {
        return;
    }
}

//
// handlePropertyChangeForFileStream:fileStreamPropertyID:ioFlags:
//
// Object method which handles implementation of MyPropertyListenerProc
//
// Parameters:
//    inAudioFileStream - should be the same as self->audioFileStream
//    inPropertyID - the property that changed
//    ioFlags - the ioFlags passed in
//
- (void)handlePropertyChangeForFileStream:(AudioFileStreamID)inAudioFileStream
                     fileStreamPropertyID:(AudioFileStreamPropertyID)inPropertyID
                                  ioFlags:(UInt32 *)ioFlags
{
    @synchronized(self)
    {
        if ([self isFinishing])
        {
            return;
        }
        
        if (inPropertyID == kAudioFileStreamProperty_ReadyToProducePackets)
        {
            discontinuous = true;
        }
        else if (inPropertyID == kAudioFileStreamProperty_DataOffset)
        {
            SInt64 offset;
            UInt32 offsetSize = sizeof(offset);
            err = AudioFileStreamGetProperty(inAudioFileStream, kAudioFileStreamProperty_DataOffset, &offsetSize, &offset);
            if (err)
            {
                [self failWithErrorCode:AS_FILE_STREAM_GET_PROPERTY_FAILED];
                return;
            }
            dataOffset = offset;
            
            if (audioDataByteCount)
            {
                fileLength = dataOffset + audioDataByteCount;
            }
        }
        else if (inPropertyID == kAudioFileStreamProperty_AudioDataByteCount) // get property: audioDataByteCount
        {
            UInt32 byteCountSize = sizeof(UInt64);
            err = AudioFileStreamGetProperty(inAudioFileStream, kAudioFileStreamProperty_AudioDataByteCount, &byteCountSize, &audioDataByteCount);
            if (err)
            {
                [self failWithErrorCode:AS_FILE_STREAM_GET_PROPERTY_FAILED];
                return;
            }
            fileLength = dataOffset + audioDataByteCount;
        }
        else if (inPropertyID == kAudioFileStreamProperty_DataFormat) // get property: absd
        {
            if (asbd.mSampleRate == 0)
            {
                UInt32 asbdSize = sizeof(asbd);
                
                // get the stream format.
                err = AudioFileStreamGetProperty(inAudioFileStream, kAudioFileStreamProperty_DataFormat, &asbdSize, &asbd);
                if (err)
                {
                    [self failWithErrorCode:AS_FILE_STREAM_GET_PROPERTY_FAILED];
                    return;
                }
            }
        }
        else if (inPropertyID == kAudioFileStreamProperty_FormatList)
        {
            Boolean outWriteable;
            UInt32 formatListSize;
            err = AudioFileStreamGetPropertyInfo(inAudioFileStream, kAudioFileStreamProperty_FormatList, &formatListSize, &outWriteable);
            if (err)
            {
                [self failWithErrorCode:AS_FILE_STREAM_GET_PROPERTY_FAILED];
                return;
            }
            
            AudioFormatListItem *formatList = malloc(formatListSize);
            err = AudioFileStreamGetProperty(inAudioFileStream, kAudioFileStreamProperty_FormatList, &formatListSize, formatList);
            if (err)
            {
                [self failWithErrorCode:AS_FILE_STREAM_GET_PROPERTY_FAILED];
                return;
            }
            
            for (int i = 0; i * sizeof(AudioFormatListItem) < formatListSize; i += sizeof(AudioFormatListItem))
            {
                AudioStreamBasicDescription pasbd = formatList[i].mASBD;
                
                if (pasbd.mFormatID == kAudioFormatMPEG4AAC_HE)
                {
                    //
                    // We've found HE-AAC, remember this to tell the audio queue
                    // when we construct it.
                    //
#if !TARGET_IPHONE_SIMULATOR
                    asbd = pasbd;
#endif
                    break;
                }                                
            }
            free(formatList);
        }
        else
        {
            //			NSLog(@"Property is %c%c%c%c",
            //				((char *)&inPropertyID)[3],
            //				((char *)&inPropertyID)[2],
            //				((char *)&inPropertyID)[1],
            //				((char *)&inPropertyID)[0]);
        }
    }
}

//
// handleAudioPackets:numberBytes:numberPackets:packetDescriptions:
//
// Object method which handles the implementation of MyPacketsProc
//
// Parameters:
//    inInputData - the packet data
//    inNumberBytes - byte size of the data
//    inNumberPackets - number of packets in the data
//    inPacketDescriptions - packet descriptions
//
- (void)handleAudioPackets:(const void *)inInputData
               numberBytes:(UInt32)inNumberBytes
             numberPackets:(UInt32)inNumberPackets
        packetDescriptions:(AudioStreamPacketDescription *)inPacketDescriptions;
{
    @synchronized(self)
    {
        if ([self isFinishing])
        {
            return;
        }
        
        if (bitRate == 0)
        {
            //
            // m4a and a few other formats refuse to parse the bitrate so
            // we need to set an "unparseable" condition here. If you know
            // the bitrate (parsed it another way) you can set it on the
            // class if needed.
            //
            bitRate = ~0;
        }
        
        // we have successfully read the first packests from the audio stream, so
        // clear the "discontinuous" flag
        if (discontinuous)
        {
            discontinuous = false;
        }
        
        if (!audioQueue)
        {
            [self createQueue];
        }
    }
    
    // the following code assumes we're streaming VBR data. for CBR data, the second branch is used.
    if (inPacketDescriptions)
    {
        for (int i = 0; i < inNumberPackets; ++i)
        {
            SInt64 packetOffset = inPacketDescriptions[i].mStartOffset;
            SInt64 packetSize   = inPacketDescriptions[i].mDataByteSize;
            size_t bufSpaceRemaining;
            
            if (processedPacketsCount < BitRateEstimationMaxPackets)
            {
                processedPacketsSizeTotal += packetSize;
                processedPacketsCount += 1;
            }
            
            @synchronized(self)
            {
                // If the audio was terminated before this point, then
                // exit.
                if ([self isFinishing])
                {
                    return;
                }
                
                if (packetSize > packetBufferSize)
                {
                    [self failWithErrorCode:AS_AUDIO_BUFFER_TOO_SMALL];
                }
                
                bufSpaceRemaining = packetBufferSize - bytesFilled;
            }
            
            // if the space remaining in the buffer is not enough for this packet, then enqueue the buffer.
            if (bufSpaceRemaining < packetSize)
            {
                [self enqueueBuffer];
            }
            
            @synchronized(self)
            {
                // If the audio was terminated while waiting for a buffer, then
                // exit.
                if ([self isFinishing])
                {
                    return;
                }
                
                //
                // If there was some kind of issue with enqueueBuffer and we didn't
                // make space for the new audio data then back out
                //
                if (bytesFilled + packetSize > packetBufferSize)
                {
                    return;
                }
                
                // copy data to the audio queue buffer
                AudioQueueBufferRef fillBuf = audioQueueBuffer[fillBufferIndex];
                memcpy((char*)fillBuf->mAudioData + bytesFilled, (const char*)inInputData + packetOffset, packetSize);
                
                // fill out packet description
                packetDescs[packetsFilled] = inPacketDescriptions[i];
                packetDescs[packetsFilled].mStartOffset = bytesFilled;
                // keep track of bytes filled and packets filled
                bytesFilled += packetSize;
                packetsFilled += 1;
            }
            
            // if that was the last free packet description, then enqueue the buffer.
            size_t packetsDescsRemaining = kAQMaxPacketDescs - packetsFilled;
            if (packetsDescsRemaining == 0) {
                [self enqueueBuffer];
            }
        }	
    }
    else
    {
        size_t offset = 0;
        while (inNumberBytes)
        {
            // if the space remaining in the buffer is not enough for this packet, then enqueue the buffer.
            size_t bufSpaceRemaining = kAQDefaultBufSize - bytesFilled;
            if (bufSpaceRemaining < inNumberBytes)
            {
                [self enqueueBuffer];
            }
            
            @synchronized(self)
            {
                // If the audio was terminated while waiting for a buffer, then
                // exit.
                if ([self isFinishing])
                {
                    return;
                }
                
                bufSpaceRemaining = kAQDefaultBufSize - bytesFilled;
                size_t copySize;
                if (bufSpaceRemaining < inNumberBytes)
                {
                    copySize = bufSpaceRemaining;
                }
                else
                {
                    copySize = inNumberBytes;
                }
                
                //
                // If there was some kind of issue with enqueueBuffer and we didn't
                // make space for the new audio data then back out
                //
                if (bytesFilled > packetBufferSize)
                {
                    return;
                }
                
                // copy data to the audio queue buffer
                AudioQueueBufferRef fillBuf = audioQueueBuffer[fillBufferIndex];
                memcpy((char*)fillBuf->mAudioData + bytesFilled, (const char*)(inInputData + offset), copySize);
                
                
                // keep track of bytes filled and packets filled
                bytesFilled += copySize;
                packetsFilled = 0;
                inNumberBytes -= copySize;
                offset += copySize;
            }
        }
    }
}

//
// handleBufferCompleteForQueue:buffer:
//
// Handles the buffer completetion notification from the audio queue
//
// Parameters:
//    inAQ - the queue
//    inBuffer - the buffer
//
- (void)handleBufferCompleteForQueue:(AudioQueueRef)inAQ
                              buffer:(AudioQueueBufferRef)inBuffer
{
    unsigned int bufIndex = -1;
    for (unsigned int i = 0; i < kNumAQBufs; ++i)
    {
        if (inBuffer == audioQueueBuffer[i])
        {
            bufIndex = i;
            break;
        }
    }
    
    if (bufIndex == -1)
    {
        [self failWithErrorCode:AS_AUDIO_QUEUE_BUFFER_MISMATCH];
        pthread_mutex_lock(&queueBuffersMutex);
        pthread_cond_signal(&queueBufferReadyCondition);
        pthread_mutex_unlock(&queueBuffersMutex);
        return;
    }
    
    // signal waiting thread that the buffer is free.
    pthread_mutex_lock(&queueBuffersMutex);
    inuse[bufIndex] = false;
    buffersUsed--;
    
    //
    //  Enable this logging to measure how many buffers are queued at any time.
    //
#if LOG_QUEUED_BUFFERS
    NSLog(@"Queued buffers: %ld", buffersUsed);
#endif
    
    pthread_cond_signal(&queueBufferReadyCondition);
    pthread_mutex_unlock(&queueBuffersMutex);
}

//
// handlePropertyChangeForQueue:propertyID:
//
// Implementation for MyAudioQueueIsRunningCallback
//
// Parameters:
//    inAQ - the audio queue
//    inID - the property ID
//
- (void)handlePropertyChangeForQueue:(AudioQueueRef)inAQ
                          propertyID:(AudioQueuePropertyID)inID
{
    @synchronized(self)
    {
        if (inID == kAudioQueueProperty_IsRunning)
        {
            if (state == AS_STOPPING)
            {
                self.state = AS_STOPPED;
            }
            else if (state == AS_WAITING_FOR_QUEUE_TO_START)
            {
                //
                // Note about this bug avoidance quirk:
                //
                // On cleanup of the AudioQueue thread, on rare occasions, there would
                // be a crash in CFSetContainsValue as a CFRunLoopObserver was getting
                // removed from the CFRunLoop.
                //
                // After lots of testing, it appeared that the audio thread was
                // attempting to remove CFRunLoop observers from the CFRunLoop after the
                // thread had already deallocated the run loop.
                //
                // By creating an NSRunLoop for the AudioQueue thread, it changes the
                // thread destruction order and seems to avoid this crash bug -- or
                // at least I haven't had it since (nasty hard to reproduce error!)
                //
                [NSRunLoop currentRunLoop];
                
                self.state = AS_PLAYING;
            }
            else
            {
                NSLog(@"AudioQueue changed state in unexpected way.");
            }
        }
    }
}


//  中断状态改变处理
- (void)handleInterruptionChangeToState:(AudioQueuePropertyID)inInterruptionState 
{
    //  中断开始，如果处于播放状态则暂停
    if (inInterruptionState == kAudioSessionBeginInterruption)
    { 
        if ([self isPlaying]) {
            [self pause];
            
            pausedByInterruption = YES; 
        } 
    }
    
    //  中断结束，如果由于之前的中断导致的播放暂停，则继续播放
    else if (inInterruptionState == kAudioSessionEndInterruption) 
    {
        AudioSessionSetActive( true );
        if ([self isPaused] && pausedByInterruption) {
            [self pause]; //在该方法中进行判断并且继续播放
            pausedByInterruption = NO; 
        }
    }
}

@end



