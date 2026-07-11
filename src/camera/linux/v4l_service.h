#ifndef _UVC_SERVICE_H_INCLUDED_
#define _UVC_SERVICE_H_INCLUDED_

#include "../video_source.h"
#include "v4l_mmap_buffer.h"
#include "v4l_headers.h"
#include "v4l_stream.h"

#include <vector>
#include <array>



class v4l_service : public VideoSource {
private:
	int m_fd;
	struct v4l2_capability m_cap;
	struct v4l2_format m_fmt;
    V4L::single_stream m_read_buffers = V4L::single_stream(V4L2_BUF_TYPE_VIDEO_CAPTURE);
    
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
    V4L::mplane_stream m_enc_buffers_write = V4L::mplane_stream(V4L2_BUF_TYPE_VIDEO_OUTPUT_MPLANE);
    V4L::mplane_stream m_enc_buffers_read = V4L::mplane_stream(V4L2_BUF_TYPE_VIDEO_CAPTURE_MPLANE);
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