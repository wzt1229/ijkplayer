//
//  ijkblurayfsprotocol.h
//  IJKMediaPlayerKit
//
//  Created by Reach Matt on 2024/9/13.
//

#ifndef ijkblurayfsprotocol_h
#define ijkblurayfsprotocol_h

#include <stdint.h>

/**
 * File access
 */
typedef struct bd_file_s BD_FILE_H;
struct bd_file_s
{
    /** Reserved for BD_FILE_H implementation use.
     *  Implementation can store here ex. file handle, FILE*, ...
     */
    void* internal;

    /**
     *  Close file
     *
     *  @param file BD_FILE_H object
     */
    void    (*close) (BD_FILE_H *file);

    /**
     *  Reposition file offset
     *
     *  - SEEK_SET: seek to 'offset' bytes from file start
     *  - SEEK_CUR: seek 'offset' bytes from current position
     *  - SEEK_END: seek 'offset' bytes from file end
     *
     *  @param file BD_FILE_H object
     *  @param offset byte offset
     *  @param origin SEEK_SET, SEEK_CUR or SEEK_END
     *  @return current file offset, < 0 on error
     */
    int64_t (*seek)  (BD_FILE_H *file, int64_t offset, int32_t origin);

    /**
     *  Get current read or write position
     *
     *  @param file BD_FILE_H object
     *  @return current file offset, < 0 on error
     */
    int64_t (*tell)  (BD_FILE_H *file);

    /**
     *  Check for end of file
     *
     *  - optional, currently not used
     *
     *  @param file BD_FILE_H object
     *  @return 1 on EOF, < 0 on error, 0 if not EOF
     */
    int     (*eof)   (BD_FILE_H *file);

    /**
     *  Read from file
     *
     *  @param file BD_FILE_H object
     *  @param buf buffer where to store the data
     *  @param size bytes to read
     *  @return number of bytes read, 0 on EOF, < 0 on error
     */
    int64_t (*read)  (BD_FILE_H *file, uint8_t *buf, int64_t size);

    /**
     *  Write to file
     *
     *  Writing 0 bytes can be used to flush previous writes and check for errors.
     *
     *  @param file BD_FILE_H object
     *  @param buf data to be written
     *  @param size bytes to write
     *  @return number of bytes written, < 0 on error
     */
    int64_t (*write) (BD_FILE_H *file, const uint8_t *buf, int64_t size);
};

/**
 * Directory entry
 */

typedef struct
{
    char    d_name[256];  /**< Null-terminated filename */
} BD_DIRENT;

/**
 * Directory access
 */

typedef struct bd_dir_s BD_DIR_H;
struct bd_dir_s
{
    void* internal; /**< reserved for BD_DIR_H implementation use */

    /**
     *  Close directory stream
     *
     *  @param dir BD_DIR_H object
     */
    void (*close)(BD_DIR_H *dir);

    /**
     *  Read next directory entry
     *
     *  @param dir BD_DIR_H object
     *  @param entry BD_DIRENT where to store directory entry data
     *  @return 0 on success, 1 on EOF, <0 on error
     */
    int (*read)(BD_DIR_H *dir, BD_DIRENT *entry);
};

/* application provided file system access (optional) */
typedef struct fs_access {
    void *fs_handle;

    /* method 1: block (device) access */
    int (*read_blocks)(void *fs_handle, void *buf, int lba, int num_blocks);

    /* method 2: file access */
    struct bd_dir_s  *(*open_dir) (void *fs_handle, const char *rel_path);
    struct bd_file_s *(*open_file)(void *fs_handle, const char *rel_path);
} fs_access;

#endif /* ijkblurayfsprotocol_h */
