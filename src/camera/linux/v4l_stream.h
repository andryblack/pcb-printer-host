#pragma once

#include "v4l_headers.h"
#include "v4l_mmap_buffer.h"
#include <vector>

namespace V4L {

    struct buffer_base {
        struct v4l2_buffer buf;
        bool queued = false;
        bool queue(int fd);
    };

    class stream_base {
    protected:
        const v4l2_buf_type m_buffer_type;
        int m_fd = -1;  
    protected:
        explicit stream_base(v4l2_buf_type type) : m_buffer_type(type) {}

        template <typename Buf,typename Prepare>
        bool allocate_impl(std::vector<Buf>& buffers,int fd,size_t num_buffers,Prepare prepare);
        template <typename Buf>
        bool queue_all_impl(std::vector<Buf>& buffers);
        template <typename Buf>
        bool queue_impl(std::vector<Buf>& buffers,size_t index);
        template <typename Buf>
        bool dequeue_impl(std::vector<Buf>& buffers,struct v4l2_buffer& buf);
        void release();
    public:
        bool start();
        bool stop();        
    };

    struct single_buffer : buffer_base {
        mmap_buffer mmap_buf; 
        bool allocate(int fd);
    };

    class single_stream : public stream_base {
    protected:
        std::vector<single_buffer> m_buffers;
    public:
        single_stream(v4l2_buf_type type) : stream_base(type) {}
        bool allocate(int fd,size_t num_buffers);
        bool queue_all();
        bool queue(size_t index);
        bool dequeue(struct v4l2_buffer& buf);
        single_buffer& get_buffer(size_t index) { return m_buffers[index]; }
        void release();
    };

    struct mplane_buffer : buffer_base {
        std::vector<mmap_buffer> mmap_bufs;
        std::vector<struct v4l2_plane> planes;
        bool allocate(int fd);
    };

    class mplane_stream : public stream_base {
    protected:
        std::vector<mplane_buffer> m_buffers;
        size_t m_num_planes = 0;
    public:
        mplane_stream(v4l2_buf_type type) : stream_base(type) {}
        bool allocate(int fd,size_t num_buffers,size_t num_planes);
        bool queue_all();
        bool queue(size_t index);
        bool dequeue(struct v4l2_buffer& buf,std::vector<struct v4l2_plane>& planes);
        mplane_buffer& get_buffer(size_t index) { return m_buffers[index]; }
        void release();
        bool get_free(size_t& index);
    };

}