// -*- coding: UTF-8, tab-width: 2 -*-
/*

I use VLC 3.0.9.2 to play a file that's currently being downloaded (a live
stream being recorded). Sometimes I start playback late, or pause playback,
and then increase playback speed to catch up. However, when I miss the
catch-up moment, VLC encounters the current end-of-file (EOF), so it thinks
the video has ended, and stops playback. That's annoying in my scenario.
This LC_PRELOAD library attempts to hide the EOF condition from VLC,
instead waiting patiently for more bytes to arrive.

The easiest way to use it with this auto-injector:
    https://github.com/mk-pmb/ld-preload-autocompile-pmb

*/

#define _GNU_SOURCE
#include <assert.h>
#include <dlfcn.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/uio.h>
#include <unistd.h>


#define STR(x) #x

#define DEBUG false
#if DEBUG
#define debug_print(fmt, ...) fprintf(stderr, "D: " fmt "\n", ##__VA_ARGS__)
#else
#define debug_print(...)
#endif

#define READV__INPUT_MEDIA_FD_MIN 25
#define READV__INPUT_MEDIA_FD_MAX 35
const useconds_t USLEEP_ONE_SECOND = 1e6;
const useconds_t READV_RETRY_DELAY = USLEEP_ONE_SECOND * 1.0;


void find_orig_func(void* *ofptr, const char *ofname) {
  if (*ofptr) { return; }
  *ofptr = dlsym(RTLD_NEXT, ofname);
  if (*ofptr) { return; }
  fprintf(stderr, "Error: dlsym(RTLD_NEXT, %s): %s\n", ofname, dlerror());
  exit(60);
}


bool readv__str_ends_with(const char *str, const char *suffix) {
  size_t str_len = strlen(str);
  size_t suffix_len = strlen(suffix);
  if (str_len < suffix_len) return false;
  return strncmp(str + str_len - suffix_len, suffix, suffix_len) == 0;
}


bool readv__guess_input_fd_is_media_file(int fd) {
  char link[1024];
  sprintf(link, "/proc/self/fd/%d", fd);
  static const size_t max_dest_path_length = 1023;
  char dest[max_dest_path_length + 1];
  ssize_t len = readlink(link, dest, max_dest_path_length);
  if (len < 0) {
    fprintf(stderr, "E: readlink() failed for %s\n", link);
    return false;
  }
  if (len < 1) { return false; }
  debug_print("readlink(%s) = '%s'", link, dest);
  if ((size_t)len >= max_dest_path_length) { return false; }
  dest[len] = '\0';
  if (readv__str_ends_with(dest, ".mkv")) { return true; }
  if (readv__str_ends_with(dest, ".mp3")) { return true; }
  if (readv__str_ends_with(dest, ".mp4")) { return true; }
  if (readv__str_ends_with(dest, ".ts")) { return true; }
  return false;
}


ssize_t readv(int fd, const struct iovec *iov, int iovcnt) {
  static ssize_t (*impl)(int fd, const struct iovec *iov, int iovcnt) = NULL;
  static int rejected_fd = READV__INPUT_MEDIA_FD_MIN - 1;
  static int accepted_fd = 0;
  find_orig_func((void**)&impl, "readv");

  ssize_t bytes_read_step = impl(fd, iov, iovcnt);
  if (bytes_read_step < 0) { return bytes_read_step; }
  if (iovcnt != 1) { return bytes_read_step; }
  if (fd <= rejected_fd) { return bytes_read_step; }
  if (fd > READV__INPUT_MEDIA_FD_MAX) { return bytes_read_step; }
  debug_print("Using injected readv(fd=%d)."
    " accepted = %d, rejected = %d", fd, accepted_fd, rejected_fd);
  if (accepted_fd) {
    if (fd != accepted_fd) { return bytes_read_step; }
  } else if (readv__guess_input_fd_is_media_file(fd)) {
    debug_print("Injected readv(): accepting fd %d.", fd);
    accepted_fd = fd;
  } else {
    debug_print("Injected readv(): rejecting fd %d.", fd);
    rejected_fd = fd;
    return bytes_read_step;
  }

  ssize_t total_bytes_requested = (ssize_t)iov[0].iov_len;
  ssize_t total_bytes_read = bytes_read_step;
  ssize_t bytes_remaining = total_bytes_requested - total_bytes_read;

  struct iovec remaining_buffer_iovec;
  // NB: Since arrays in C are just pointers, we do not an array here.
  //  Giving an array of length 1 is exactly the same as giving the address
  //  of its first element, so we can just use &remaining_buffer_iovec.
  //  For the same reason, the upcoming `[0].` syntax is equivalent to `->`.

  char* remaining_buffer_ptr = (char*)iov[0].iov_base;
  remaining_buffer_ptr += bytes_read_step;

  while (bytes_remaining > 0) {
    debug_print("Incomplete readv(fd=%d), we need %lu more bytes. Sleeping.",
      fd, bytes_remaining);
    usleep(READV_RETRY_DELAY);

    // NB: iov_len is always in bytes, independent of the buffer's data type.
    remaining_buffer_iovec.iov_base = remaining_buffer_ptr;
    remaining_buffer_iovec.iov_len = (size_t)bytes_remaining;
    bytes_read_step = impl(fd, &remaining_buffer_iovec, iovcnt);

    debug_print("We obtained %ld more bytes.", bytes_read_step);
    if (bytes_read_step < 0) { return bytes_read_step; }
    if (bytes_read_step > 0) {
      remaining_buffer_ptr += bytes_read_step;
      total_bytes_read += bytes_read_step;
      bytes_remaining -= bytes_read_step;
    }
  }

  assert(total_bytes_requested == total_bytes_read);
  return total_bytes_read;
}
