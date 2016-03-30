//
//  AudioPlayer.m
//  BearAudioQueueDemo
//
//  Created by Bear on 15/11/5.
//  Copyright © 2015年 Bear. All rights reserved.
//

#import "AudioPlayer.h"

@implementation AudioPlayer

#pragma mark 播放
- (void)play{

    if (!_streamer) {
        self.streamer = [[AudioStreamer alloc] initWithURL:_url];
        
        //  打包更新进度条的方法
        SEL selector = @selector(updateProgress);
        NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:[self methodSignatureForSelector:selector]];
        [invocation setSelector:selector];
        [invocation setTarget:self];
        
        //  每隔0.1秒更新进度条位置
        timer = [NSTimer scheduledTimerWithTimeInterval:0.1
                                             invocation:invocation
                                                repeats:YES];

        // 如果播放状态改变的话切换播放／停止图标
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(playStateChanged:)
                                                     name:ASStatusChangedNotification
                                                   object:_streamer];
    }
    
    [_streamer start];
    [_playBtn setTitle:@"暂停" forState:UIControlStateNormal];
}


#pragma mark 暂停播放
- (void)pause{
    [_streamer pause];
    [_playBtn setTitle:@"播放" forState:UIControlStateNormal];
}


#pragma mark 停止播放
- (void)stop{
    _slider.value = 0.0f;
    [_streamer stop];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:ASStatusChangedNotification object:_streamer];
    _streamer = nil;
    [_playBtn setTitle:@"播放" forState:UIControlStateNormal];
}


#pragma mark 更新进度条
- (void)updateProgress
{
    if (_streamer.progress <= _streamer.duration ) {
        _slider.value = _streamer.progress/_streamer.duration;
    } else {
        _slider.value = 0;
    }
}


#pragma mark 监听播放状态改变
- (void)playStateChanged:(NSNotification *)notification
{
    if ([_streamer isWaiting])
    {
        
    } else if ([_streamer isIdle]) {
        [self stop];
    } else if ([_streamer isPaused]) {
        
    } else if ([_streamer isPlaying] || [_streamer isFinishing]) {
        
    } else {
        
    }
}


@end
