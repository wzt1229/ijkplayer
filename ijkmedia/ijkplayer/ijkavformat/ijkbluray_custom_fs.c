//
//  ijkbluray_custom_fs_smb2.c
//  IJKMediaPlayerKit
//
//  Created by Reach Matt on 2024/9/13.
//

#include "ijkbluray_custom_fs.h"
#include "ijkblurayfsprotocol.h"
#include "ijk_custom_io_smb2_impl.h"
#include "ijk_custom_io_http_impl.h"

#include <libavutil/mem.h>
#include <libavutil/avstring.h>

#ifndef UDF_BLOCK_SIZE
#  define UDF_BLOCK_SIZE  2048
#endif

static int read_blocks(void *fs_handle, void *buf, int lba, int num_blocks)
{
    ijk_custom_io_protocol * io = fs_handle;
    int got = -1;
    int64_t pos = (int64_t)lba * UDF_BLOCK_SIZE;
    
    /* seek + read must be atomic */
    io->seek(io, pos, SEEK_SET);
    int64_t bytes = io->read(io, (uint8_t*)buf, num_blocks * UDF_BLOCK_SIZE);
    if (bytes > 0) {
        got = (int)(bytes / UDF_BLOCK_SIZE);
    }
    return got;
}

void ijk_destroy_bluray_custom_access(fs_access **p)
{
    if (p) {
        fs_access *access = *p;
        if (access) {
            ijk_custom_io_protocol *io = access->fs_handle;
            if (io) {
                io->destroy(&io);
            }
        }
        av_freep(p);
    }
}

// 构建fs_access结构体
fs_access * ijk_create_bluray_custom_access(const char *url) 
{
    ijk_custom_io_protocol *io = NULL;
    if (av_strstart(url, "smb2", NULL)) {
        io = ijk_custom_io_create_smb2(url);
    } else if (av_strstart(url, "http", NULL) || av_strstart(url, "https", NULL)) {
        io = ijk_custom_io_create_http(url);
    }
    
    if (io) {
        fs_access *access = av_malloc(sizeof(fs_access));
        access->fs_handle = io;
        access->read_blocks = read_blocks;
        return access;
    }
    return NULL;
}
