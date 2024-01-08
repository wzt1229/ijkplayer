//
//  IJKISOTools.m
//  IJKMediaPlayerKit
//
//  Created by Reach Matt on 2023/12/19.
//

#import "IJKISOTools.h"
#include <libbluray/bluray.h>
#include <dvdread/dvd_reader.h>
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
    const char *disc_root = [discRoot UTF8String];
    if (!disc_root) {
        return NO;
    }
    const char *keyfile = keyFile ? [keyFile UTF8String] : NULL;
    
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
