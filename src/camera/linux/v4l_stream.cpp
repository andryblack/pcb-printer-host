#include "v4l_stream.h"
#include "llae/logger.h"

namespace V4L {

    bool buffer_base::queue(int fd) {
        if (queued) {
            LOG_ERROR("stream_base::buffer_base::queue already queued" );
            return false;
        }
        auto ret = IOCTL_VIDEO(fd, VIDIOC_QBUF, &buf);
        if (ret < 0) {
            LOG_ERROR("buffers_ring::queue failed queue buffer " << ret );
            return false;
        }
        queued = true;
        return true;
    }

    bool stream_base::start() {
        if (m_fd < 0) {
            LOG_ERROR("Stream not opened");
            return false;
        }
        int type = m_buffer_type;
        auto ret = IOCTL_VIDEO(m_fd, VIDIOC_STREAMON, &type);
        if(ret < 0) {
            LOG_ERROR("Unable to start stream");
            return false;
        }
        return true;
    }

    bool stream_base::stop() {
        if (m_fd < 0) {
            LOG_ERROR("Stream not opened");
            return false;
        }
        int type = m_buffer_type;
        auto ret = IOCTL_VIDEO(m_fd, VIDIOC_STREAMOFF, &type);
        if(ret < 0) {
            LOG_ERROR("Unable to stop stream");
            return false;
        }
        return true;
    }

    void stream_base::release() {
        m_fd = -1;
    }
   
    template <typename Buf,typename Prepare>
    bool stream_base::allocate_impl(std::vector<Buf>& buffers,int fd,size_t num_buffers,Prepare prepare) {
        if (m_fd >= 0) {
            LOG_ERROR("Stream already opened");
            return false;
        }
        if (!buffers.empty()) {
            LOG_ERROR("Stream already allocated");
            return false;
        }

        struct v4l2_requestbuffers rb;
        ::memset(&rb, 0, sizeof(rb));
        rb.count = num_buffers;
        rb.type = m_buffer_type;
        rb.memory = V4L2_MEMORY_MMAP;

        auto ret = IOCTL_VIDEO(fd, VIDIOC_REQBUFS, &rb);
        if(ret < 0) {
            LOG_ERROR("Unable to request buffers " << ret);
            return false;
        }
        buffers.resize(num_buffers);
        size_t index = 0;
        for (auto& b:buffers) {
            b.buf.index = index++;
            b.buf.type = m_buffer_type;
            prepare(b);
            b.allocate(fd);
        }
        
        m_fd = fd;
        return true;
    }

    template <typename Buf>
    bool stream_base::queue_all_impl(std::vector<Buf>& buffers) {
        if (m_fd < 0) {
            LOG_ERROR("Stream not opened");
            return false;
        }
        for (auto& b:buffers) {
            if (!b.queue(m_fd)) {
                return false;
            }
        }
        return true;
    }

    template <typename Buf>
    bool stream_base::queue_impl(std::vector<Buf>& buffers,size_t index) {
        if (m_fd < 0) {
            LOG_ERROR("Stream not opened");
            return false;
        }
        if (index >= buffers.size()) {
            LOG_ERROR("Invalid buffer index");
            return false;
        }
        return buffers[index].queue(m_fd);
    }

    template <typename Buf>
    bool stream_base::dequeue_impl(std::vector<Buf>& buffers,struct v4l2_buffer& buf) {
        if (m_fd < 0) {
            LOG_ERROR("Stream not opened");
            return false;
        }
        buf.type = m_buffer_type;
        buf.memory = V4L2_MEMORY_MMAP;
        int ret = IOCTL_VIDEO(m_fd, VIDIOC_DQBUF, &buf);
        if(ret < 0) {
            LOG_ERROR("stream_base::dequeue_impl failed dequeue buffer " << ret);
            return false;
        }
        if (buf.index < buffers.size()) {
            buffers[buf.index].queued = false;
        }
        return true;
    }

    bool single_buffer::allocate(int fd) {
        buf.memory = V4L2_MEMORY_MMAP;
        auto ret = IOCTL_VIDEO(fd, VIDIOC_QUERYBUF, &buf);
        if (ret < 0) {
            LOG_ERROR("single_stream::buffer::allocate failed to query enc buffe" << ret);
            return false;
        }
        if (!mmap_buf.allocate(buf.length,fd,buf.m.offset)) {
            LOG_ERROR("single_stream::buffer::allocate failed to allocate buffer " << buf.index);
            return false;
        }
        return true;
    }

    

    bool single_stream::allocate(int fd,size_t num_buffers) {
        return allocate_impl(m_buffers,fd,num_buffers,[](single_buffer& b){

        });
    }

    bool single_stream::queue_all() {
        return queue_all_impl(m_buffers);
    }

    bool single_stream::queue(size_t index) {
        return queue_impl(m_buffers,index);
    }

    bool single_stream::dequeue(struct v4l2_buffer& buf) {
        return dequeue_impl(m_buffers,buf);
    }

    void single_stream::release() {
        m_buffers.clear();
        stream_base::release();
    }

    bool mplane_buffer::allocate(int fd) {
        buf.memory = V4L2_MEMORY_MMAP;
        auto ret = IOCTL_VIDEO(fd, VIDIOC_QUERYBUF, &buf);
        if (ret < 0) {
            LOG_ERROR("mplane_buffer::allocate failed to query enc buffe" << ret);
            return false;
        }
        for (size_t i=0;i<buf.length;++i) {
            if (i >= mmap_bufs.size()) {
                LOG_ERROR("invalid mmap_bufs.size");
                return false;
            }
            if (!mmap_bufs[i].allocate(buf.m.planes[i].length,fd,buf.m.planes[i].m.mem_offset)) {
                LOG_ERROR("mplane_buffer::allocate failed to allocate buffer " << buf.index);
                return false;
            }
        }
        return true;
    }

    bool mplane_stream::allocate(int fd,size_t num_buffers, size_t num_planes) {
        m_num_planes = num_planes;
        return allocate_impl(m_buffers,fd,num_buffers,[num_planes](mplane_buffer& b){
            b.planes.resize(num_planes);
            b.mmap_bufs.resize(num_planes);
            b.buf.length = num_planes;
            b.buf.m.planes = b.planes.data();
        });
    }

    bool mplane_stream::queue_all() {
        return queue_all_impl(m_buffers);
    }

    bool mplane_stream::queue(size_t index) {
        return queue_impl(m_buffers,index);
    }

    bool mplane_stream::dequeue(struct v4l2_buffer& buf,std::vector<struct v4l2_plane>& planes) {
        buf.length = m_num_planes;
        planes.resize(m_num_planes);
        buf.m.planes = planes.data();
        if (dequeue_impl(m_buffers,buf)) {
            planes.resize(buf.length);
            buf.m.planes = planes.data();
            return true;
        }
        return false;
    }

    bool mplane_stream::get_free(size_t& index) {
        for (size_t i=0;i<m_buffers.size();++i) {
            if (!m_buffers[i].queued) {
                index = i;
                return true;
            }
        }
        return false;
    }

    void mplane_stream::release() {
        m_buffers.clear();
        stream_base::release();
    }
    
}