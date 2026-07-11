#ifndef _UVC_SERVICE_H_INCLUDED_
#define _UVC_SERVICE_H_INCLUDED_

#include "../video_source.h"

#define IOCTL_VIDEO(fd, req, value) ::ioctl(fd, req, value)
#define OPEN_VIDEO(fd, flags) ::open(fd, flags)
#define CLOSE_VIDEO(fd) ::close(fd)

#include <linux/kernel.h>
#include <linux/types.h>          /* for videodev2.h */
#include <linux/videodev2.h>
#include <vector>
#include <array>

static const size_t NUM_BUFFERS = 4;

class mmapped_buffer {
private:
    void *m_mem = nullptr;
    size_t m_size = 0;
public:
    mmapped_buffer();
    mmapped_buffer(mmapped_buffer&& r);
    ~mmapped_buffer();
    void release();
    bool allocate(int fd,struct v4l2_buffer& buf);
    bool allocate_mp(int fd,struct v4l2_buffer& buf);
    void* get_mem() { return m_mem; }
};

class buffers_ring {
private:
    std::array<mmapped_buffer,NUM_BUFFERS> m_buffers;
    std::array<bool,NUM_BUFFERS> m_queued;
    v4l2_buf_type m_type;
public:
    explicit buffers_ring(v4l2_buf_type type);
    void release();
    bool allocate(int fd);
    bool allocate_mp(int fd);
    void* get_mem(size_t index) { return m_buffers[index].get_mem(); }
    bool queue(int fd,struct v4l2_buffer& buf);
    bool dequeue(int fd,struct v4l2_buffer& buf);
    void queue_all(int fd);
    bool get_free(size_t& index);
};

class v4l_service : public VideoSource {
private:
	int m_fd;
	struct v4l2_capability m_cap;
	struct v4l2_format m_fmt;
    buffers_ring m_read_buffers = buffers_ring(V4L2_BUF_TYPE_VIDEO_CAPTURE);
    
    volatile bool m_active;
    volatile bool m_started;
    uv_thread_t m_read_thread;
    void process_frame();
    void process_enc_frame();
    static void read_thread_func(void* arg);
    void read_thread(); 
    void start_thread();
    void stop_thread();
    bool m_need_encode;
    
    int m_enc_fd;
    struct v4l2_capability m_enc_cap;
    buffers_ring m_enc_buffers_write = buffers_ring(V4L2_BUF_TYPE_VIDEO_CAPTURE_MPLANE);
    buffers_ring m_enc_buffers_read = buffers_ring(V4L2_BUF_TYPE_VIDEO_OUTPUT_MPLANE);
    std::vector<struct v4l2_buffer> m_enc_out_buffers;
    bool open_jpeg_encoder(lua::state& l);
    size_t jpeg_encode(const void* src,size_t src_size);
public:
	v4l_service();
	~v4l_service();

	virtual void close() override;
	virtual bool open(lua::state& l) override;

	virtual void start() override;
	virtual void stop() override;
};

#endif /*_UVC_SERVICE_H_INCLUDED_*/