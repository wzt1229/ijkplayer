/*
 * Copyright (C) 2013-2015 Bilibili
 * Copyright (C) 2013-2015 Zhang Rui <bbcallen@gmail.com>
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#import "IJKDemoSampleViewController.h"

#import "IJKCommon.h"
#import "IJKMoviePlayerViewController.h"

@interface IJKDemoSampleViewController () <UITableViewDataSource, UITableViewDelegate>

@property(nonatomic,strong) IBOutlet UITableView *tableView;
@property(nonatomic,strong) NSArray *sampleList;

@end

@implementation IJKDemoSampleViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = @"M3U8";

    NSMutableArray *sampleList = [[NSMutableArray alloc] init];

    NSString *str =@"ffconcat version 1.0";
    
    NSArray *urls = @[@"http://27.209.180.18/sohu/p2p/TGwgoEHUTGPUTCsRaf-MSk-8Sm59xLvmsfMwJCs-sSxN49rA/fhXdmQTJ?key=3yQMcAar-gluGEHRF81nQSJulGN6BFEhUBElQg..&q=bj0yJmE8mhiamA&rs=1&hash=NQ7EI4JQSWIXC2PAWT3WMT25CETKYX6Q&size=38154214&plat=ifox_mac&ch=tv&catcode=101100;101104;101107&uid=12B84742-2781-4C08-85D8-9C6EB21B03E9",
      @"http://27.209.180.10/sohu/p2p/TGwgoExyTGQUTGhqtwxiS5Y5JSv8-CsTj5xUXSkFsAHN49rA/2MpD9PPE?key=ZgUITZn2FhP_a8IavIF_-chfZNxss-7VqMylNw..&q=bj0yJmE8mhiamA&rs=1&hash=V4KXOKN5CRJHOUOAZUUZWVHFTY6IEMFF&size=38203424&plat=ifox_mac&ch=tv&catcode=101100;101104;101107&uid=12B84742-2781-4C08-85D8-9C6EB21B03E9",
      @"http://27.209.180.20/sohu/p2p/TGQgoGrgo6oGTm1YxSqhXAXak5HiaWhgqvhDsCXNaLQN49rA/XAACIwGV?key=Pi9V35dCRYQ-M5ER8cVseXiCGrbA7bNizJhE9A..&q=bj0yJmE8mhiamA&rs=1&hash=LSGJPPFGX3YTCEG3MY4NRQZPSSAIJ74F&size=38177980&plat=ifox_mac&ch=tv&catcode=101100;101104;101107&uid=12B84742-2781-4C08-85D8-9C6EB21B03E9",
      @"http://27.209.180.14/sohu/p2p/TGogo6wATGwyqKVl05rGqS2ijwkWSCulqam6JauqawXoTlmyqr/f8P35O9x?key=8X6MTOLFxpwd7tJOIGIMvUXoDgbGELbAKAKLxQ..&q=bj0yJmE8mhiamA&rs=1&hash=G3ZP2BQUDB4AVJJPJA57GCQYQZLE4KP4&size=38143053&plat=ifox_mac&ch=tv&catcode=101100;101104;101107&uid=12B84742-2781-4C08-85D8-9C6EB21B03E9"
                      ];
    
    for (NSString *url in urls) {
        
        str = [NSString stringWithFormat:@"%@\nhttp %@\nduration %.0f",str,url,300.0];
        
    }
    
    NSLog(@"分片视频数据：%@",str);
    
    [sampleList addObject:@[@"多段mp4",
                            @"http://localhost:8080/ffmpeg-test/test.ffcat"]];
    
    
    [sampleList addObject:@[@"las url",
    @"{\"version\":\"1.0.0\",\"adaptationSet\":[{\"duration\":1000,\"id\":1,\"representation\":[{\"id\":1,\"codec\":\"avc1.64001e,mp4a.40.5\",\"url\":\"http://las-tech.org.cn/kwai/las-test_ld500d.flv\",\"backupUrl\":[],\"host\":\"las-tech.org.cn\",\"maxBitrate\":700,\"width\":640,\"height\":360,\"frameRate\":25,\"qualityType\":\"SMOOTH\",\"qualityTypeName\":\"流畅\",\"hidden\":false,\"disabledFromAdaptive\":false,\"defaultSelected\":false},{\"id\":2,\"codec\":\"avc1.64001f,mp4a.40.5\",\"url\":\"http://las-tech.org.cn/kwai/las-test_sd1000d.flv\",\"backupUrl\":[],\"host\":\"las-tech.org.cn\",\"maxBitrate\":1300,\"width\":960,\"height\":540,\"frameRate\":25,\"qualityType\":\"STANDARD\",\"qualityTypeName\":\"标清\",\"hidden\":false,\"disabledFromAdaptive\":false,\"defaultSelected\":false},{\"id\":3,\"codec\":\"avc1.64001f,mp4a.40.5\",\"url\":\"http://las-tech.org.cn/kwai/las-test.flv\",\"backupUrl\":[],\"host\":\"las-tech.org.cn\",\"maxBitrate\":2300,\"width\":1280,\"height\":720,\"frameRate\":30,\"qualityType\":\"HIGH\",\"qualityTypeName\":\"高清\",\"hidden\":false,\"disabledFromAdaptive\":false,\"defaultSelected\":true}]}]}"]]; 
    [sampleList addObject:@[@"bipbop basic master playlist",
                            @"http://devimages.apple.com.edgekey.net/streaming/examples/bipbop_4x3/bipbop_4x3_variant.m3u8"]];
    [sampleList addObject:@[@"bipbop basic 400x300 @ 232 kbps",
                            @"http://devimages.apple.com.edgekey.net/streaming/examples/bipbop_4x3/gear1/prog_index.m3u8"]];
    [sampleList addObject:@[@"bipbop basic 640x480 @ 650 kbps",
                            @"http://devimages.apple.com.edgekey.net/streaming/examples/bipbop_4x3/gear2/prog_index.m3u8"]];
    [sampleList addObject:@[@"bipbop basic 640x480 @ 1 Mbps",
                            @"http://devimages.apple.com.edgekey.net/streaming/examples/bipbop_4x3/gear3/prog_index.m3u8"]];
    [sampleList addObject:@[@"bipbop basic 960x720 @ 2 Mbps",
                            @"http://devimages.apple.com.edgekey.net/streaming/examples/bipbop_4x3/gear4/prog_index.m3u8"]];
    [sampleList addObject:@[@"bipbop basic 22.050Hz stereo @ 40 kbps",
                            @"http://devimages.apple.com.edgekey.net/streaming/examples/bipbop_4x3/gear0/prog_index.m3u8"]];

    [sampleList addObject:@[@"bipbop advanced master playlist",
                            @"http://devimages.apple.com.edgekey.net/streaming/examples/bipbop_16x9/bipbop_16x9_variant.m3u8"]];
    [sampleList addObject:@[@"bipbop advanced 416x234 @ 265 kbps",
                            @"http://devimages.apple.com.edgekey.net/streaming/examples/bipbop_16x9/gear1/prog_index.m3u8"]];
    [sampleList addObject:@[@"bipbop advanced 640x360 @ 580 kbps",
                            @"http://devimages.apple.com.edgekey.net/streaming/examples/bipbop_16x9/gear2/prog_index.m3u8"]];
    [sampleList addObject:@[@"bipbop advanced 960x540 @ 910 kbps",
                            @"http://devimages.apple.com.edgekey.net/streaming/examples/bipbop_16x9/gear3/prog_index.m3u8"]];
    [sampleList addObject:@[@"bipbop advanced 1280x720 @ 1 Mbps",
                            @"http://devimages.apple.com.edgekey.net/streaming/examples/bipbop_16x9/gear4/prog_index.m3u8"]];
    [sampleList addObject:@[@"bipbop advanced 1920x1080 @ 2 Mbps",
                            @"http://devimages.apple.com.edgekey.net/streaming/examples/bipbop_16x9/gear5/prog_index.m3u8"]];
    [sampleList addObject:@[@"bipbop advanced 22.050Hz stereo @ 40 kbps",
                            @"http://devimages.apple.com.edgekey.net/streaming/examples/bipbop_16x9/gear0/prog_index.m3u8"]];

    self.sampleList = sampleList;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];

    [self.tableView reloadData];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return @"Samples";
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (IOS_NEWER_OR_EQUAL_TO_7) {
        return self.sampleList.count;
    } else {
        return self.sampleList.count - 1;
    }
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"abc"];
    if (nil == cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"abc"];
        cell.textLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    }

    cell.textLabel.text = self.sampleList[indexPath.row][0];

    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    NSArray *item = self.sampleList[indexPath.row];
    NSString *url_str = item[1];
    
    if ([url_str containsString:@"adaptationSet"]) {
        [self.navigationController presentViewController:[[IJKVideoViewController alloc] initWithManifest:url_str] animated:YES completion:^{}];
    } else{
        NSURL   *url  = [NSURL URLWithString:item[1]];
        [self.navigationController presentViewController:[[IJKVideoViewController alloc] initWithURL:url] animated:YES completion:^{}];
    }
}

@end
