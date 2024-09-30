//
//  IJKISOTools.m
//  IJKMediaPlayerKit
//
//  Created by Reach Matt on 2023/12/19.
//

#import "IJKISOTools.h"

#include <libavutil/avstring.h>
#include <libbluray/bluray.h>
#include <dvdread/dvd_reader.h>
#include "../../ijksdl/ijksdl_log.h"
#include <libavformat/bluray_util.h>

@implementation IJKISOTools

+ (BOOL)isDVDVideo:(NSString *)discRoot
{
    const char *disc_root = [discRoot UTF8String];
    if (!disc_root) {
        return NO;
    }
    dvd_reader_t *dvd = DVDOpen(disc_root);
    if (!dvd) {
        ALOGE("DVDOpen can't open\n");
        return NO;
    }
    dvd_file_t *file = DVDOpenFile(dvd, 0, DVD_READ_INFO_BACKUP_FILE);
    if(!file) {
        ALOGE("DVDOpenFile can't open BACKUP_FILE\n");
        file = DVDOpenFile(dvd, 0, DVD_READ_INFO_BACKUP_FILE);
    }
    if(!file) {
        ALOGE("DVDOpenFile can't open INFO_FILE\n");
        DVDClose(dvd);
        return NO;
    } else {
        DVDCloseFile(file);
        DVDClose(dvd);
        return YES;
    }
}

+ (BOOL)isBlurayVideo:(NSString *)discRoot keyFile:(NSString *)keyFile
{
    const char *diskname = [discRoot UTF8String];
    if (!diskname) {
        ALOGE("BD disc root can't be empty\n");
        return NO;
    }
    
    return ff_is_bluray_video(diskname, NULL);
}

@end
