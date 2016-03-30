//
//  AudioPlayer.h
//  BearAudioQueueDemo
//
//  Created by Bear on 15/11/5.
//  Copyright © 2015年 Bear. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "AudioStreamer.h"
#import <UIKit/UIKit.h>

@interface AudioPlayer : NSObject{
    NSTimer *timer;
}

@property (nonatomic, strong) UISlider      *slider;
@property (strong, nonatomic) UIButton      *playBtn;
@property (strong, nonatomic) UIButton      *stopBtn;

@property (nonatomic, retain) NSURL         *url;
@property (nonatomic, retain) AudioStreamer *streamer;

- (void)play;
- (void)stop;
- (void)pause;

@end
