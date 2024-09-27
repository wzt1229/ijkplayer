//
//  ijkbluray_custom_fs.h
//  IJKMediaPlayerKit
//
//  Created by Reach Matt on 2024/9/13.
//

#ifndef ijkbluray_custom_fs_h
#define ijkbluray_custom_fs_h

#include <stdio.h>

typedef struct fs_access fs_access;
typedef struct AVDictionary AVDictionary;
void ijk_destroy_bluray_custom_access(fs_access **p);
fs_access * ijk_create_bluray_custom_access(const char *url, AVDictionary **options);
#endif /* ijkbluray_custom_fs_smb2_h */
