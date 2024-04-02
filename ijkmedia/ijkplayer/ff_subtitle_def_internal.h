//
//  ff_subtitle_def_internal.h
//  IJKMediaPlayerKit
//
//  Created by Reach Matt on 2024/3/28.
//

#ifndef ff_subtitle_def_internal_hpp
#define ff_subtitle_def_internal_hpp

#include "ff_subtitle_def.h"

FFSubtitleBuffer *ff_subtitle_buffer_alloc_image(SDL_Rectangle rect, int bpc);
FFSubtitleBuffer *ff_subtitle_buffer_alloc_text(const char *text);

void ff_subtitle_buffer_append_text(FFSubtitleBuffer* sb, const char *text);

#endif /* ff_subtitle_def_internal_hpp */
