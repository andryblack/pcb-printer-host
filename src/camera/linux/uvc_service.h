#ifndef _UVC_SERVICE_H_INCLUDED_
#define _UVC_SERVICE_H_INCLUDED_

#include "../video_source.h"

#define IOCTL_VIDEO(fd, req, value) ::ioctl(fd, req, value)
#define OPEN_VIDEO(fd, flags) ::open(fd, flags)
#define CLOSE_VIDEO(fd) ::close(fd)

#include <linux/kernel.h>
#include <linux/types.h>          /* for videodev2.h */
#include <linux/videodev2.h>

static const size_t NUM_BUFFERS = 4;

class uvc_service : public VideoSource {
private:
	int m_fd;
	struct v4l2_capability m_cap;
	struct v4l2_format m_fmt;
    struct v4l2_buffer m_buf;
    struct v4l2_requestbuffers m_rb;
    void *m_buffers_mem[NUM_BUFFERS];
    size_t m_sizes[NUM_BUFFERS];
    volatile bool m_active;
    volatile bool m_started;
    uv_thread_t m_read_thread;
    void process_frame();
    static void read_thread_func(void* arg);
    void read_thread(); 
    void start_thread();
    void stop_thread();
    bool m_need_encode;
    char m_encode_buffer[640*480*2];
public:
	uvc_service();
	~uvc_service();

	virtual void close() override;
	virtual bool open(lua::state& l) override;

	virtual void start() override;
	virtual void stop() override;
};

#endif /*_UVC_SERVICE_H_INCLUDED_*/