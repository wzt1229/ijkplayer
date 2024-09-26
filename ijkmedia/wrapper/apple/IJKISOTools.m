//
//  IJKISOTools.m
//  IJKMediaPlayerKit
//
//  Created by Reach Matt on 2023/12/19.
//

#import "IJKISOTools.h"

#include <libavutil/avstring.h>
#include <libavformat/urldecode.h>
#include <libbluray/bluray.h>
#include <dvdread/dvd_reader.h>
#include "../../ijkplayer/ijkavformat/ijkblurayfsprotocol.h"
#include "../../ijkplayer/ijkavformat/ijkbluray_custom_fs.h"
#include "../../ijksdl/ijksdl_log.h"

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
    
    fs_access *access = NULL;
    if (av_strstart(diskname, "file://", NULL) || av_strstart(diskname, "/", NULL)) {
        access = NULL;
    } else {
        access = ijk_create_bluray_custom_access(diskname);
    }
    
    const char *keyfile = keyFile ? [keyFile UTF8String] : NULL;
    BLURAY *bd = bd_open_fs(diskname, keyfile, access);
    if (!bd) {
        return NO;
    }
    
    bd_close(bd);
    ijk_destroy_bluray_custom_access(&access);
    return YES;
}

@end
