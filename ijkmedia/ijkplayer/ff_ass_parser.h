//
//  ff_ass_parser.h
//  IJKMediaPlayerKit
//
//  Created by Reach Matt on 2022/5/17.
//

#ifndef ff_ass_parser_h
#define ff_ass_parser_h

typedef struct FFSubtitleBuffer FFSubtitleBuffer;
//need free the return value! see av_free();
void parse_ass_subtitle(const char *ass, FFSubtitleBuffer **sb);

#endif /* ff_ass_parser_h */
