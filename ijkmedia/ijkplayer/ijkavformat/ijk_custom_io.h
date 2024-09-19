//
//  ijk_custom_io.h
//  IJKMediaPlayerKit
//
//  Created by Reach Matt on 2024/9/19.
//

#ifndef ijk_custom_io_h
#define ijk_custom_io_h

#include <stdio.h>
 
typedef struct ijk_custom_io_protocol ijk_custom_io_protocol;

typedef struct ijk_custom_io_protocol {
    void *opaque;
    int (*read)(ijk_custom_io_protocol *, uint8_t *buf, int buf_size);
    int (*write)(ijk_custom_io_protocol *, uint8_t *buf, int buf_size);
    //origin:SEEK_SET,SEEK_CUR,SEEK_END
    int64_t (*seek)(ijk_custom_io_protocol *, int64_t offset, int origin);
    //current file offset, < 0 on error
    int64_t (*tell)(ijk_custom_io_protocol *);
    //return 1 on EOF, < 0 on error, 0 if not EOF
    int (*eof)(ijk_custom_io_protocol *);
    int64_t (*file_size)(ijk_custom_io_protocol *);
    void (*destroy)(ijk_custom_io_protocol **);
} ijk_custom_io_protocol;

#endif /* ijk_custom_io_h */
