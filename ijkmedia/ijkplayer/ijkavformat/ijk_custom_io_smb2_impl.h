//
//  ijk_custom_io_smb2_impl.h
//  IJKMediaPlayerKit
//
//  Created by Reach Matt on 2024/9/19.
//
// smb2 对 custom io 的实现
// smb2://user:password@host/share/video/4.mp4
//

#ifndef ijk_custom_io_smb2_impl_h
#define ijk_custom_io_smb2_impl_h

#include "ijk_custom_io.h"

ijk_custom_io_protocol * ijk_custom_io_create_smb2(const char *url);

#endif /* ijk_custom_io_smb2_impl_h */
