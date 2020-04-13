#include "uvc_service.h"
#include <sys/ioctl.h>
#include <sys/time.h>
#include <errno.h>
#include <unistd.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/mman.h>

#include <linux/types.h>          /* for videodev2.h */
#include <linux/videodev2.h>

#include "luabind.h"
#if defined(USE_VC_HW_ENCODING) 
#include "rpi_jpeg_encoder.h"
#define jpeg_encoder_finish rpi_jpeg_encoder_finish
#define jpeg_encoder_init rpi_jpeg_encoder_init
#define jpeg_encode rpi_jpeg_encode
#else
static void jpeg_encoder_finish() {}
static size_t jpeg_encode(const void* src_data,void* dst_data) {
    return 0;
}
static bool jpeg_encoder_init(size_t img_width, size_t img_height) {
    return false;
}
#endif

#define HEADERFRAME1 0xaf

uvc_service::uvc_service() : m_fd(-1),m_read_thread(0),m_active(false),m_started(false) {
    m_need_encode = false;
    memset(m_buffers_mem,0,sizeof(m_buffers_mem));
}

static const char* vf_tostr(int vf) {
	switch (vf) {
		case V4L2_PIX_FMT_MJPEG: return "MJPEG";
		case V4L2_PIX_FMT_JPEG: return "JPEG";
		case V4L2_PIX_FMT_YUYV: return "YUYV";
		case V4L2_PIX_FMT_UYVY: return "UYVY";
		case V4L2_PIX_FMT_RGB565: return "RGB565";
	}
	return "unknown";
}

uvc_service::~uvc_service() {
	close();
}
void uvc_service::close() {

    if (m_need_encode) {
        jpeg_encoder_finish();
    }

	m_need_encode = false;

	m_active = false;
	stop_thread();

    for (size_t i=0;i<NUM_BUFFERS;++i) {
        if (m_buffers_mem[i]) {
            munmap(m_buffers_mem[i],m_sizes[i]);
            m_buffers_mem[i] = 0;
        }
    }

	if (m_fd != -1) {
		CLOSE_VIDEO(m_fd);
		m_fd = -1;
	}

}

bool uvc_service::open(lua_State* L) {
	close();
	const char* dev = lua_tostring(L,2);
	if((m_fd = OPEN_VIDEO(dev, O_RDWR)) == -1) {
        printf("ERROR opening V4L interface %s\n",dev);
        return false;
    }
    memset(&m_cap, 0, sizeof(struct v4l2_capability));
    int ret = IOCTL_VIDEO(m_fd, VIDIOC_QUERYCAP, &m_cap);
    if(ret < 0) {
        printf("ERROR unable to query capabilities.\n");
        return false;
    }
    if((m_cap.capabilities & V4L2_CAP_VIDEO_CAPTURE) == 0) {
        printf("ERROR video capture not supported.\n");
        return false;
    }
    if(!(m_cap.capabilities & V4L2_CAP_STREAMING)) {
        printf("ERROR does not support streaming i/o\n");
        return false;
    }

    int width = 640;
    int height = 480;

    memset(&m_fmt, 0, sizeof(struct v4l2_format));
    
    m_fmt.type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
    if (IOCTL_VIDEO(m_fd, VIDIOC_G_FMT, &m_fmt) == 0) {
        printf("Current size: %dx%d\n",
             m_fmt.fmt.pix.width,
             m_fmt.fmt.pix.height);
    }

    m_fmt.fmt.pix.width = width;
    m_fmt.fmt.pix.height = height;
    m_fmt.fmt.pix.pixelformat = V4L2_PIX_FMT_MJPEG;
    m_fmt.fmt.pix.field = V4L2_FIELD_ANY;
    ret = IOCTL_VIDEO(m_fd, VIDIOC_S_FMT, &m_fmt);
    if(ret < 0) {
        printf("ERROR unable to set MPEG format\n");
        memset(&m_fmt, 0, sizeof(struct v4l2_format));
        m_fmt.fmt.pix.width = width;
        m_fmt.fmt.pix.height = height;
        m_fmt.fmt.pix.pixelformat = V4L2_PIX_FMT_YUYV;
        m_fmt.fmt.pix.field = V4L2_FIELD_ANY;
        ret = IOCTL_VIDEO(m_fd, VIDIOC_S_FMT, &m_fmt);
        if(ret < 0) {
            printf("ERROR unable to set YUYV format\n");
            return false;
        }
    }
    width = m_fmt.fmt.pix.width;
    height = m_fmt.fmt.pix.height;
    printf("using: %dx%d\n",width,height);
    if (m_fmt.fmt.pix.pixelformat != V4L2_PIX_FMT_MJPEG) {
        if (m_fmt.fmt.pix.pixelformat == V4L2_PIX_FMT_YUYV) {
            if (jpeg_encoder_init(width,height)) {
                m_need_encode = true;
            } else {
                printf("ERROR failed init jpeg encoder\n");
                return false;
            }
        } else {
        	printf("ERROR usupported pixel format: %d (%s)\n",m_fmt.fmt.pix.pixelformat,vf_tostr(m_fmt.fmt.pix.pixelformat));
            return false;
        }
    }

    memset(&m_rb, 0, sizeof(struct v4l2_requestbuffers));
    m_rb.count = NUM_BUFFERS;
    m_rb.type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
    m_rb.memory = V4L2_MEMORY_MMAP;

    ret = IOCTL_VIDEO(m_fd, VIDIOC_REQBUFS, &m_rb);
    if(ret < 0) {
        printf("Unable to allocate buffers\n");
        return false;
    }
    for(size_t i = 0; i < NUM_BUFFERS; i++) {
        memset(&m_buf, 0, sizeof(struct v4l2_buffer));
        m_buf.index = i;
        m_buf.type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
        m_buf.memory = V4L2_MEMORY_MMAP;
        ret = IOCTL_VIDEO(m_fd, VIDIOC_QUERYBUF, &m_buf);
        if(ret < 0) {
            printf("Unable to query buffer %d\n",i);
            return false;
        }

		m_buffers_mem[i] = mmap(0 /* start anywhere */ ,
                          m_buf.length, PROT_READ | PROT_WRITE, MAP_SHARED, m_fd,
                          m_buf.m.offset);
        m_sizes[i] = m_buf.length;
        if(m_buffers_mem[i] == MAP_FAILED) {
            printf("Unable to map buffer\n");
            return false;
        }
    }

    
    

    m_active = true;
    return true;
}

void uvc_service::start_thread() {
	uv_thread_create(&m_read_thread,&read_thread_func,this);
}

void uvc_service::stop_thread() {
	if (m_read_thread) {
		uv_thread_join(&m_read_thread);
		m_read_thread = 0;
	}
}

void uvc_service::read_thread_func(void * arg) {
	static_cast<uvc_service*>(arg)->read_thread();
}

void uvc_service::read_thread() {
	printf("read_thread started\n");
	while (m_active && m_started) {
		fd_set rd_fds;
		FD_ZERO(&rd_fds);
        FD_SET(m_fd, &rd_fds);
        struct timeval tv;
        tv.tv_sec = 1.0;
        tv.tv_usec = 0;
        int sel = select(m_fd + 1, &rd_fds, 0, 0, &tv);
        if (sel < 0) {
            if (errno == EINTR) {
                continue;
            }
            printf("Select error %d\n",errno);
            break;
        } else if (sel == 0) {
        	continue;
        }
        if (FD_ISSET(m_fd, &rd_fds)) {
        	process_frame();
        }
	}
	printf("read_thread ended\n");
}

void uvc_service::process_frame() {
	if (!m_started) {
		return;
	}
	memset(&m_buf, 0, sizeof(struct v4l2_buffer));
    m_buf.type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
    m_buf.memory = V4L2_MEMORY_MMAP;

    int ret = IOCTL_VIDEO(m_fd, VIDIOC_DQBUF, &m_buf);
    if(ret < 0) {
        printf("Unable to dequeue buffer\n");
        return;
    }
    if(m_buf.bytesused > HEADERFRAME1 && m_need_frame) { 
    	
        if (m_need_encode) {
            size_t frame_size = jpeg_encode(m_buffers_mem[m_buf.index],m_encode_buffer);
            if (frame_size) {
                put_frame(m_encode_buffer,frame_size,m_buf.timestamp);
            } 
        } else {
            put_frame(m_buffers_mem[m_buf.index], m_buf.bytesused,m_buf.timestamp);
        }

    }
    

    ret = IOCTL_VIDEO(m_fd, VIDIOC_QBUF, &m_buf);
    if(ret < 0) {
        printf("Unable to queue buffer\n");
        return;
    }

}

void uvc_service::start() {
	if (m_started) {
		return;
	}

	for(size_t i = 0; i < NUM_BUFFERS; ++i) {
        memset(&m_buf, 0, sizeof(struct v4l2_buffer));
        m_buf.index = i;
        m_buf.type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
        m_buf.memory = V4L2_MEMORY_MMAP;
        int ret = IOCTL_VIDEO(m_fd, VIDIOC_QBUF, &m_buf);
        if(ret < 0) {
            printf("start: Unable to queue buffer %d\n",i);
        }
    }

	int type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
    int ret;

    ret = IOCTL_VIDEO(m_fd, VIDIOC_STREAMON, &type);
    if(ret < 0) {
        printf("Unable to start capture\n");
        return;
    }
    printf("stream started\n");
    m_started = true;
    start_thread();
}

void uvc_service::stop() {
	if (!m_started) {
		return;
	}
	int type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
    int ret;
    ret = IOCTL_VIDEO(m_fd, VIDIOC_STREAMOFF, &type);
    if(ret != 0) {
        printf("Unable to stop capture\n");
        return;
    }
    printf("stream stopped\n");
    m_started = false;
    stop_thread();
}


int VideoSource::lnew(lua_State* L) {
	(new uvc_service())->push(L);
	return 1;
}
