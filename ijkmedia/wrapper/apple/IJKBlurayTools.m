//
//  IJKBlurayTools.m
//  IJKMediaPlayerKit
//
//  Created by Reach Matt on 2023/12/19.
//

#import "IJKBlurayTools.h"
#include <libbluray/bluray.h>
#include "../../ijksdl/ijksdl_log.h"

@implementation IJKBlurayTools

+ (BOOL)isBlurayVideo:(NSString *)discRoot keyFile:(NSString *)keyFile
{
    const char *disc_root = [discRoot UTF8String];
    const char *keyfile   = keyFile ? [keyFile UTF8String] : NULL;
    
    int major, minor, micro;

    bd_get_version(&major, &minor, &micro);
    ALOGD("Using libbluray version %d.%d.%d\n", major, minor, micro);

    if (!disc_root) {
        ALOGE("BD disc root can't be empty\n");
        return NO;
    }

    BLURAY *bd = bd_open(disc_root, keyfile);
    if (!bd) {
        return NO;
    }
    bd_close(bd);
    return YES;
}

@end
