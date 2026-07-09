#include "v4l_service.h"
#include <sys/ioctl.h>
#include <sys/time.h>
#include <errno.h>
#include <unistd.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/mman.h>

#include <linux/types.h>          /* for videodev2.h */
#include <linux/videodev2.h>

#include <llae/logger.h>
#include <lua/bind.h>


mmapped_buffer::mmapped_buffer() {

}

mmapped_buffer::mmapped_buffer(mmapped_buffer&& o) : m_mem(o.m_mem), m_size(o.m_size) {
    o.m_mem = nullptr;
}

void mmapped_buffer::release() {
    if (m_mem) {
        munmap(m_mem,m_size);
        m_mem = nullptr;
    }
}

bool mmapped_buffer::allocate(int fd, struct v4l2_buffer& buf) {
    if (m_mem) {
        LOG_ERROR("mmapped_buffer::allocate already allocated");
        return false;
    }

    auto mem = mmap(0 /* start anywhere */ ,
                          buf.length, PROT_READ | PROT_WRITE, MAP_SHARED, fd,
                          buf.m.offset);
    if(mem == MAP_FAILED) { 
        LOG_ERROR("mmapped_buffer::allocate mmap failed");
        return false;
    }
    m_size = buf.length;
    m_mem = mem;
    return true;
}

bool mmapped_buffer::allocate_mp(int fd, struct v4l2_buffer& buf) {
    if (m_mem) {
        LOG_ERROR("mmapped_buffer::allocate_mp already allocated");
        return false;
    }

    if (buf.length != 1) {
        LOG_ERROR("mmapped_buffer::allocate_mp unexpected planes " << buf.length);
        return false;
    }

    auto& plane = buf.m.planes[0];

    auto mem = mmap(0 /* start anywhere */ ,
                          plane.length, PROT_READ | PROT_WRITE, MAP_SHARED, fd,
                          plane.m.mem_offset);
    if(mem == MAP_FAILED) { 
        LOG_ERROR("mmapped_buffer::alloc mmap failed");
        return false;
    }
    m_size = plane.length;
    m_mem = mem;
    return true;
}

mmapped_buffer::~mmapped_buffer() {
    release();
}

buffers_ring::buffers_ring(v4l2_buf_type type) : m_type(type) {
    for (auto& v:m_queued) {
        v = false;
    }
}

void buffers_ring::release() {
    for (auto& b:m_buffers) {
        b.release();
    }
    for (auto& v:m_queued) {
        v = false;
    }
}

bool buffers_ring::allocate(int fd) {
    
    struct v4l2_buffer buf;
    size_t index = 0;
    for (auto& b:m_buffers) {
        memset(&buf, 0, sizeof(buf));
        buf.index = index++;
        buf.type = m_type;
        buf.memory = V4L2_MEMORY_MMAP;
        auto ret = IOCTL_VIDEO(fd, VIDIOC_QUERYBUF, &buf);
        if (ret < 0) {
            LOG_ERROR("buffers_ring::allocate failed to query enc buffe" << ret);
            return false;
        }
        if (!b.allocate(fd,buf)) {
            return false;
        }
    }
    return true;
}

bool buffers_ring::allocate_mp(int fd) {
    
    struct v4l2_buffer buf;
    size_t index = 0;
    for (auto& b:m_buffers) {
        memset(&buf, 0, sizeof(buf));
        buf.index = index++;
        buf.type = m_type;
        buf.memory = V4L2_MEMORY_MMAP;
        auto ret = IOCTL_VIDEO(fd, VIDIOC_QUERYBUF, &buf);
        if (ret < 0) {
            LOG_ERROR("buffers_ring::allocate failed to query enc buffe" << ret);
            return false;
        }
        if (!b.allocate_mp(fd,buf)) {
            return false;
        }
    }
    return true;
}

bool buffers_ring::queue(int fd,struct v4l2_buffer& buf) {
    if (m_queued[buf.index]) {
        LOG_ERROR("buffers_ring::queue already queued" );
        return false;
    }
    auto ret = IOCTL_VIDEO(fd, VIDIOC_QBUF, &buf);
    if (ret < 0) {
        LOG_ERROR("buffers_ring::queue failed queue buffer " << ret );
        return false;
    } else {
        m_queued[buf.index] = true;
        return true;
    }
}

bool buffers_ring::dequeue(int fd,struct v4l2_buffer& buf) {
    memset(&buf, 0, sizeof(buf));
    buf.type = m_type;
    buf.memory = V4L2_MEMORY_MMAP;
    int ret = IOCTL_VIDEO(fd, VIDIOC_DQBUF, &buf);
    if(ret < 0) {
        LOG_ERROR("buffers_ring::dequeue failed dequeue buffer " << ret);
        return false;
    }
    m_queued[buf.index] = 0;
    return true;
}

void buffers_ring::queue_all(int fd) {
    struct v4l2_buffer buf;
    size_t index = 0;
    for (auto& b:m_buffers) {
        memset(&buf, 0, sizeof(buf));
        buf.index = index++;
        if (m_queued[buf.index]) {
             continue;
        }
        buf.type = m_type;
        buf.memory = V4L2_MEMORY_MMAP;
        queue(fd,buf);
    }
}

bool buffers_ring::get_free(size_t& index) {
    index = 0;
    for (auto& b:m_queued) {
        if (b) return true;
        ++index;
    }
    return false;
}

#define HEADERFRAME1 0xaf

v4l_service::v4l_service() : m_fd(-1),m_read_thread(0),m_active(false),m_started(false),m_enc_fd(-1) {
    m_need_encode = false;
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

v4l_service::~v4l_service() {
	close();
}
void v4l_service::close() {

   

	m_need_encode = false;

	m_active = false;
	stop_thread();

    m_read_buffers.release();
    m_enc_buffers_write.release();
    m_enc_buffers_read.release();

	if (m_fd != -1) {
		CLOSE_VIDEO(m_fd);
		m_fd = -1;
	}
    if (m_enc_fd != -1) {
        CLOSE_VIDEO(m_enc_fd);
        m_enc_fd = -1;
    }

}

static const char* get_fmt_str(uint32_t fmt) {
     switch(fmt) {
        case V4L2_PIX_FMT_MJPEG:
            return "MJPEG";
            break;
        case V4L2_PIX_FMT_YUYV:
            return "YUYV";
            break;
        case V4L2_PIX_FMT_RGB24:
            return "RGB24";
            break;
        case V4L2_PIX_FMT_BGR24:
            return "BGR24";
            break;
        case V4L2_PIX_FMT_RGB565:
            return "RGB565";
            break;
        }
    static char fmt_buffer[32];
    snprintf(fmt_buffer,32,"%c%c%c%c",int(fmt&0xff),
        int((fmt>>8)&0xff),
        int((fmt>>16)&0xff),
        int((fmt>>24)&0xff));
    return fmt_buffer;
}

size_t v4l_service::jpeg_encode(const void* src,size_t src_size) {

    size_t index = 0;
    if (!m_enc_buffers_write.get_free(index)) {
        LOG_ERROR("not found free enc buffers");
        return 0;
    }
    struct v4l2_buffer buf;
    buf.index = index;
    ::memcpy(m_enc_buffers_write.get_mem(index),src,src_size);
    struct v4l2_plane plane;
    ::memset(&plane,0,sizeof(plane));
    plane.bytesused = src_size;
    plane.data_offset = 0;
    buf.length = 1;
    buf.m.planes = &plane;
    m_enc_buffers_write.queue(m_enc_fd,buf);;

    return 0;
}

bool v4l_service::open_jpeg_encoder(lua::state& l) {
    if (!l.isstring(3)) {
        printf("Need encoder dev\n");
        return false;
    }
    const char* dev = l.tostring(3);
    if((m_enc_fd = OPEN_VIDEO(dev, O_RDWR)) == -1) {
        printf("ERROR opening V4L interface %s\n",dev);
        return false;
    }
    memset(&m_enc_cap, 0, sizeof(struct v4l2_capability));
    int ret = IOCTL_VIDEO(m_enc_fd, VIDIOC_QUERYCAP, &m_enc_cap);
    if(ret < 0) {
        printf("ERROR unable to query encoder capabilities.\n");
        return false;
    }
    printf("Encoder driver: %s, card: %s, bus: %s caps: %08x\n",m_enc_cap.driver,m_enc_cap.card,m_enc_cap.bus_info,m_enc_cap.capabilities);
    if((m_enc_cap.capabilities & ( V4L2_CAP_VIDEO_M2M_MPLANE)) == 0) {
        printf("ERROR does not support m2m i/o\n");
        return false;
    }

    struct v4l2_format inputFormat = {0};
    inputFormat.type = V4L2_BUF_TYPE_VIDEO_OUTPUT_MPLANE;
    ret = IOCTL_VIDEO(m_enc_fd, VIDIOC_G_FMT, &inputFormat);
    if(ret < 0) {
        printf("ERROR unable get encoder input format.\n");
    }
    inputFormat.fmt.pix_mp.width = m_fmt.fmt.pix.width;
    inputFormat.fmt.pix_mp.height = m_fmt.fmt.pix.height;
    inputFormat.fmt.pix_mp.pixelformat = m_fmt.fmt.pix.pixelformat;
    inputFormat.fmt.pix_mp.field = V4L2_FIELD_ANY;
    inputFormat.fmt.pix_mp.colorspace = V4L2_COLORSPACE_DEFAULT;
    inputFormat.fmt.pix_mp.num_planes = 1;

    ret = IOCTL_VIDEO(m_enc_fd, VIDIOC_S_FMT, &inputFormat);
    if(ret < 0) {
        printf("ERROR unable set encoder input format.\n");
        return false;
    }

    struct v4l2_format outputFormat = {0};
    outputFormat.type = V4L2_BUF_TYPE_VIDEO_CAPTURE_MPLANE;
    ret = IOCTL_VIDEO(m_enc_fd, VIDIOC_G_FMT, &outputFormat);
    if(ret < 0) {
        printf("ERROR unable get encoder output format.\n");
    }
    outputFormat.fmt.pix_mp.width = m_fmt.fmt.pix.width;
    outputFormat.fmt.pix_mp.height = m_fmt.fmt.pix.height;
    outputFormat.fmt.pix_mp.pixelformat = V4L2_PIX_FMT_MJPEG;
    outputFormat.fmt.pix_mp.field = V4L2_FIELD_ANY;
    outputFormat.fmt.pix_mp.colorspace = V4L2_COLORSPACE_DEFAULT;
    outputFormat.fmt.pix_mp.num_planes = 1;

    ret = IOCTL_VIDEO(m_enc_fd, VIDIOC_S_FMT, &outputFormat);
    if(ret < 0) {
        printf("ERROR unable set encoder output format.\n");
        return false;
    }


    struct v4l2_requestbuffers rb;
    memset(&rb, 0, sizeof(rb));
    rb.count = NUM_BUFFERS;
    rb.type = V4L2_BUF_TYPE_VIDEO_CAPTURE_MPLANE;
    rb.memory = V4L2_MEMORY_MMAP;

    ret = IOCTL_VIDEO(m_enc_fd, VIDIOC_REQBUFS, &rb);
    if(ret < 0) {
        printf("Unable to allocate enc capture buffers\n");
        return false;
    }

    if (!m_enc_buffers_read.allocate_mp(m_enc_fd)) {
        return false;
    }
   

    memset(&rb, 0, sizeof(rb));
    rb.count = NUM_BUFFERS;
    rb.type = V4L2_BUF_TYPE_VIDEO_OUTPUT_MPLANE;
    rb.memory = V4L2_MEMORY_MMAP;

    ret = IOCTL_VIDEO(m_enc_fd, VIDIOC_REQBUFS, &rb);
    if(ret < 0) {
        printf("Unable to allocate enc output buffers\n");
        return false;
    }

    if (!m_enc_buffers_write.allocate_mp(m_enc_fd)) {
        return false;
    }
                
    return true;
}

bool v4l_service::open(lua::state& l) {
	close();
	const char* dev = l.tostring(2);
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
    printf("Camera driver: %s, card: %s, bus: %s\n",m_cap.driver,m_cap.card,m_cap.bus_info);
    if((m_cap.capabilities & V4L2_CAP_VIDEO_CAPTURE) == 0) {
        printf("ERROR video capture not supported.\n");
        return false;
    }
    if(!(m_cap.capabilities & V4L2_CAP_STREAMING)) {
        printf("ERROR does not support streaming i/o\n");
        return false;
    }

    v4l2_input inpt;
    memset(&inpt,0,sizeof(inpt));
    inpt.index = 0;
    int found_camera_input = -1;
    while (true) {
        ret = IOCTL_VIDEO(m_fd, VIDIOC_ENUMINPUT, &inpt);
        if (ret == 0) {
            printf("Input %s type: %d\n",inpt.name,inpt.type);
            if (inpt.type == V4L2_INPUT_TYPE_CAMERA) {
                found_camera_input = inpt.index;
            }
        } else {
            auto e = errno;
            if ( e != EINVAL) {
                printf("Failed enum input: %d\n",e);
            }
            break;
        }
        ++inpt.index;
    }
    int current_camera_input = -1;
    ret = IOCTL_VIDEO(m_fd, VIDIOC_G_INPUT, &current_camera_input);
    if (ret == 0) {
        printf("Current input: %d\n",current_camera_input);
    }
    if (found_camera_input == -1 && current_camera_input == -1) {
        printf("Not found input\n");
        return false;
    } 
    ret = IOCTL_VIDEO(m_fd, VIDIOC_S_INPUT, &found_camera_input);
    if (ret != 0) {
        printf("Failed set camera input %d\n",ret);
    }

    int width = 640;
    int height = 480;

    struct v4l2_fmtdesc fmt_desc;
    fmt_desc.type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
    fmt_desc.index = 0;
    while (true) {
        ret = IOCTL_VIDEO(m_fd, VIDIOC_ENUM_FMT, &fmt_desc);
        if (ret == 0) {
            printf("Supported fmt: %s %s\n",get_fmt_str(fmt_desc.pixelformat),fmt_desc.description);
        } else {
            break;
        }
        ++fmt_desc.index;
    }

    memset(&m_fmt, 0, sizeof(struct v4l2_format));
    
    m_fmt.type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
    ret = IOCTL_VIDEO(m_fd, VIDIOC_G_FMT, &m_fmt);
    if ( ret == 0) {
        const char* fmt = get_fmt_str(m_fmt.fmt.pix.pixelformat);
        
        printf("Current size: %dx%d %s\n",
             m_fmt.fmt.pix.width,
             m_fmt.fmt.pix.height,fmt);
    } else {
        printf("Failed get current format %d\n",ret);
    }

    m_fmt.type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
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
    IOCTL_VIDEO(m_fd, VIDIOC_G_FMT, &m_fmt);
    width = m_fmt.fmt.pix.width;
    height = m_fmt.fmt.pix.height;
    printf("using: %dx%d\n",width,height);
    if (m_fmt.fmt.pix.pixelformat != V4L2_PIX_FMT_MJPEG) {
        if (m_fmt.fmt.pix.pixelformat == V4L2_PIX_FMT_YUYV) {
            if ( open_jpeg_encoder(l) ) {
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

    struct v4l2_requestbuffers rb;
    memset(&rb, 0, sizeof(rb));
    rb.count = NUM_BUFFERS;
    rb.type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
    rb.memory = V4L2_MEMORY_MMAP;

    ret = IOCTL_VIDEO(m_fd, VIDIOC_REQBUFS, &rb);
    if(ret < 0) {
        printf("Unable to allocate buffers\n");
        return false;
    }

    if (!m_read_buffers.allocate(m_fd)) {
        return false;
    }

    m_active = true;
    return true;
}

void v4l_service::start_thread() {
	uv_thread_create(&m_read_thread,&read_thread_func,this);
}

void v4l_service::stop_thread() {
	if (m_read_thread) {
		uv_thread_join(&m_read_thread);
		m_read_thread = 0;
	}
}

void v4l_service::read_thread_func(void * arg) {
	static_cast<v4l_service*>(arg)->read_thread();
}

void v4l_service::read_thread() {
	printf("read_thread started\n");
	while (m_active && m_started) {
		fd_set rd_fds;
		FD_ZERO(&rd_fds);
        FD_SET(m_fd, &rd_fds);
        int maxfd = m_fd;
        if (m_enc_fd > 0) {
            FD_SET(m_enc_fd, &rd_fds);
            if (m_enc_fd > maxfd)
                maxfd = m_enc_fd;
        }
        struct timeval tv;
        tv.tv_sec = 1.0;
        tv.tv_usec = 0;
        int sel = select(maxfd + 1, &rd_fds, 0, 0, &tv);
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
        if (m_enc_fd > 0) {
            if (FD_ISSET(m_enc_fd, &rd_fds)) {
                process_enc_frame();
            }
        }
	}
	printf("read_thread ended\n");
}

void v4l_service::process_enc_frame() {
    if (!m_started) {
        return;
    }
    struct v4l2_buffer buf;
    if (!m_enc_buffers_read.dequeue(m_enc_fd,buf)) {
        return;
    }

    for (auto i=0;i<buf.length;++i) {
        auto& p = buf.m.planes[i];
        if (p.bytesused > HEADERFRAME1 && m_need_frame) {
            put_frame(m_enc_buffers_read.get_mem(buf.index), p.bytesused,buf.timestamp);
            break;
        }
    }
    m_enc_buffers_read.queue(m_enc_fd,buf);
}

void v4l_service::process_frame() {
	if (!m_started) {
		return;
	}
    struct v4l2_buffer buf;
	if (!m_read_buffers.dequeue(m_fd,buf)) {
        return;
    }
   
    if(buf.bytesused > HEADERFRAME1 && m_need_frame) { 
    	
        if (m_need_encode) {
            jpeg_encode(m_read_buffers.get_mem(buf.index),buf.bytesused);
        } else {
            put_frame(m_read_buffers.get_mem(buf.index), buf.bytesused,buf.timestamp);
        }

    }
    
    m_read_buffers.queue(m_fd,buf);

}

void v4l_service::start() {
	if (m_started) {
		return;
	}

    m_read_buffers.queue_all(m_fd);

	

    if (m_need_encode) {
        m_enc_buffers_read.queue_all(m_enc_fd);
    }

	int type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
    int ret;

    ret = IOCTL_VIDEO(m_fd, VIDIOC_STREAMON, &type);
    if(ret < 0) {
        printf("Unable to start capture\n");
        return;
    }

    if (m_need_encode) {
        type = V4L2_BUF_TYPE_VIDEO_CAPTURE_MPLANE;
        
        ret = IOCTL_VIDEO(m_enc_fd, VIDIOC_STREAMON, &type);
        if(ret < 0) {
            printf("Unable to start enc capture\n");
            return;
        }

        type = V4L2_BUF_TYPE_VIDEO_OUTPUT_MPLANE;
        
        ret = IOCTL_VIDEO(m_enc_fd, VIDIOC_STREAMON, &type);
        if(ret < 0) {
            printf("Unable to start enc output\n");
            return;
        }

    }
    printf("stream started\n");
    m_started = true;
    start_thread();
}

void v4l_service::stop() {
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
    if (m_need_encode) {
        ret = IOCTL_VIDEO(m_enc_fd, VIDIOC_STREAMOFF, &type);
        if(ret != 0) {
            printf("Unable to stop encode\n");
            return;
        }
    }
    m_started = false;
    stop_thread();
}


lua::multiret VideoSource::lnew(lua::state& l) {
    return push(l,new v4l_service());
}
