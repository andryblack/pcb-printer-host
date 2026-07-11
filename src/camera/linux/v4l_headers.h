#pragma once

#define IOCTL_VIDEO(fd, req, value) ::ioctl(fd, req, value)
#define OPEN_VIDEO(fd, flags) ::open(fd, flags)
#define CLOSE_VIDEO(fd) ::close(fd)

#include <linux/kernel.h>
#include <linux/types.h>          /* for videodev2.h */
#include <linux/videodev2.h>

