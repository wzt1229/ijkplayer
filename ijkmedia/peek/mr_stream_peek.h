//
//  mr_stream_peek.h
//  MRISR
//
//  Created by Reach Matt on 2023/9/7.
//

#ifndef mr_stream_peek_h
#define mr_stream_peek_h

#include <stdio.h>
typedef struct MRStreamPeek MRStreamPeek;

int mr_stream_peek_create(MRStreamPeek **subp,int frameMaxCount);
int mr_stream_peek_open_filepath(MRStreamPeek *sub, const char *file_name, int idx);

int mr_stream_peek_get_opened_stream_idx(MRStreamPeek *sub);
int mr_stream_peek_seek_to(MRStreamPeek *sub, float sec);
int mr_stream_peek_get_data(MRStreamPeek *sub, unsigned char *buffer, int len, double * pts_begin, double * pts_end);
int mr_stream_peek_close(MRStreamPeek *sub);
void mr_stream_peek_destroy(MRStreamPeek **subp);
int mr_stream_peek_get_buffer_size(int millisecond);

#endif /* mr_stream_peek_h */
