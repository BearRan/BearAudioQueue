//
//  ViewController.m
//  BearAudioQueueDemo
//
//  Created by Bear on 15/11/5.
//  Copyright © 2015年 Bear. All rights reserved.
//

#import "ViewController.h"
#import "UIView+MySet.h"
#import "AudioPlayer.h"
#import "AudioStreamer.h"


//  当前屏幕宽度
#define SCREEN_WIDTH    [UIScreen mainScreen].bounds.size.width
//  当前屏幕高度
#define SCREEN_HEIGHT   [UIScreen mainScreen].bounds.size.height


@interface ViewController (){
    AudioPlayer *_audioPlayer;
    NSArray     *songArray;
    int         songIndex;
    int         songTotal;
}

@property (strong, nonatomic) UILabel   *nameLabel;
@property (strong, nonatomic) UILabel   *singerLabel;
@property (strong, nonatomic) UIButton  *nextBtn;
@property (strong, nonatomic) UIButton  *preBtn;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    //  初始化歌曲信息
    songArray = @[
                  [NSDictionary dictionaryWithObjectsAndKeys:@"最炫小水果", @"song", @"凤凰传奇－筷子兄弟", @"artise", @"http://yinyueshiting.baidu.com/data2/music/2010517041/2010517041205200128.mp3?xcode=871c0c45f5d6372490032d54ecb07301", @"url", nil],
                  [NSDictionary dictionaryWithObjectsAndKeys:@"自由自在", @"song", @"凤凰传奇", @"artise", @"http://yinyueshiting.baidu.com/data2/music/121949165/1070622207200064.mp3?xcode=cfddaa7221b7f8950fd1a9e14bd081d7", @"url", nil],
                  [NSDictionary dictionaryWithObjectsAndKeys:@"月亮之上", @"song", @"凤凰传奇", @"artise", @"http://yinyueshiting.baidu.com/data2/music/123314464/77233020880064.mp3?xcode=cfddaa7221b7f895c6826868de970894", @"url", nil],
                  [NSDictionary dictionaryWithObjectsAndKeys:@"策马奔腾", @"song", @"凤凰传奇", @"artise", @"http://yinyueshiting.baidu.com/data2/music/123319263/851348120520064.mp3?xcode=b8cd3f4a27fdb6be37ff48ca31f559c2", @"url", nil],
                  ];
    songTotal = (int)[songArray count];
    songIndex = 0;
    
    //  初始化播放器
    if (!_audioPlayer) {
        _audioPlayer = [[AudioPlayer alloc] init];
    }
    
    //  初始化界面
    [self initSetView];
}

#pragma mark 初始化界面
- (void)initSetView
{
    //  设置歌名Label
    _nameLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, SCREEN_WIDTH - 100, 20)];
    _nameLabel.text = [songArray[songIndex] objectForKey:@"song"];
    _nameLabel.textAlignment = NSTextAlignmentCenter;
    [self.view addSubview:_nameLabel];
    [_nameLabel setMyDirectionDistance:dir_Up destinationView:nil parentRelation:YES distance:100 center:YES];
    
    //  歌手Label
    _singerLabel = [[UILabel alloc] initWithFrame:_nameLabel.bounds];
    _singerLabel.text =  [NSString stringWithFormat:@"演唱者:%@", [songArray[songIndex] objectForKey:@"artise"]];
    _singerLabel.textAlignment = NSTextAlignmentCenter;
    [self.view addSubview:_singerLabel];
    [_singerLabel setMyDirectionDistance:dir_Down destinationView:_nameLabel parentRelation:NO distance:50 center:YES];
    
    //  设置停止按钮
    _audioPlayer.stopBtn = [[UIButton alloc] init];
    [_audioPlayer.stopBtn setTitle:@"停止" forState:UIControlStateNormal];
    [_audioPlayer.stopBtn setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
    [_audioPlayer.stopBtn sizeToFit];
    [self.view addSubview:_audioPlayer.stopBtn];
    [_audioPlayer.stopBtn setMyDirectionDistance:dir_Down destinationView:nil parentRelation:YES distance:50 center:YES];
    [_audioPlayer.stopBtn addTarget:self action:@selector(stopEvent:) forControlEvents:UIControlEventTouchUpInside];
    
    //  设置播放按钮
    _audioPlayer.playBtn = [[UIButton alloc] init];
    [_audioPlayer.playBtn setTitle:@"播放" forState:UIControlStateNormal];
    [_audioPlayer.playBtn setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
    [_audioPlayer.playBtn sizeToFit];
    [self.view addSubview:_audioPlayer.playBtn];
    [_audioPlayer.playBtn setMyDirectionDistance:dir_Up destinationView:_audioPlayer.stopBtn parentRelation:NO distance:20 center:YES];
    [_audioPlayer.playBtn addTarget:self action:@selector(playEvent:) forControlEvents:UIControlEventTouchUpInside];
    
    //  下一首按钮
    _nextBtn = [[UIButton alloc] init];
    [_nextBtn setTitle:@"下一首" forState:UIControlStateNormal];
    [_nextBtn setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
    [_nextBtn sizeToFit];
    [self.view addSubview:_nextBtn];
    [_nextBtn setMyDirectionDistance:dir_Right destinationView:_audioPlayer.playBtn parentRelation:NO distance:50 center:YES];
    [_nextBtn addTarget:self action:@selector(nextSongEvent) forControlEvents:UIControlEventTouchUpInside];
    
    //  上一首按钮
    _preBtn = [[UIButton alloc] init];
    [_preBtn setTitle:@"上一首" forState:UIControlStateNormal];
    [_preBtn setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
    [_preBtn sizeToFit];
    [self.view addSubview:_preBtn];
    [_preBtn setMyDirectionDistance:dir_Left destinationView:_audioPlayer.playBtn parentRelation:NO distance:50 center:YES];
    [_preBtn addTarget:self action:@selector(preSongEvent) forControlEvents:UIControlEventTouchUpInside];
    
    //  设置Slider
    _audioPlayer.slider = [[UISlider alloc] initWithFrame:CGRectMake(0, 0, SCREEN_WIDTH - 100, 20)];
    _audioPlayer.slider.enabled = NO;
    [self.view addSubview:_audioPlayer.slider];
    [_audioPlayer.slider setMyDirectionDistance:dir_Up destinationView:_audioPlayer.playBtn parentRelation:NO distance:50 center:YES];
}


#pragma mark 点击播放按钮事件
- (void)playEvent:(UIButton *)sender
{
    if ([_audioPlayer.streamer isPlaying]) {
        [_audioPlayer pause];
    }else{
        _audioPlayer.url = [NSURL URLWithString:[songArray[songIndex] objectForKey:@"url"]];
        [_audioPlayer play];
    }
}

#pragma mark 点击停止播放按钮事件
- (void)stopEvent:(UIButton *)sender
{
    [_audioPlayer stop];
}

#pragma mark 点击播放下一首事件
- (void)nextSongEvent
{
    if (songTotal > songIndex + 1) {
        songIndex++;
        [_audioPlayer stop];
        _nameLabel.text = [songArray[songIndex] objectForKey:@"song"];
        _singerLabel.text =  [NSString stringWithFormat:@"演唱者:%@", [songArray[songIndex] objectForKey:@"artise"]];
        _audioPlayer.url = [NSURL URLWithString:[songArray[songIndex] objectForKey:@"url"]];
        [_audioPlayer play];
    }else{
        NSLog(@"已经是最后一首歌了");
    }
}

#pragma mark 点击播放上一首事件
- (void)preSongEvent
{
    if (songIndex > 0) {
        songIndex--;
        [_audioPlayer stop];
        _nameLabel.text = [songArray[songIndex] objectForKey:@"song"];
        _singerLabel.text =  [NSString stringWithFormat:@"演唱者:%@", [songArray[songIndex] objectForKey:@"artise"]];
        _audioPlayer.url = [NSURL URLWithString:[songArray[songIndex] objectForKey:@"url"]];
        [_audioPlayer play];
    }else{
        NSLog(@"这是第一首歌");
    }
}

@end




