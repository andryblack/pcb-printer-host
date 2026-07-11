#include "v4l_mmap_buffer.h"
#include "llae/logger.h"

#include <unistd.h>
#include <sys/mman.h>

namespace V4L {
        
    mmap_buffer::mmap_buffer(mmapped_buffer&& o) : m_mem(o.m_mem), m_size(o.m_size) {
        o.m_mem = nullptr;
        o.m_size = 0;
    }
     
    mmap_buffer::~mmap_buffer() {
        release();
    }

    void mmap_buffer::release() {
        if (m_mem) {
            auto r = munmap(m_mem,m_size);
            if (r < 0) {
                LOG_ERROR(" failed munmap " << r);
            }
            m_mem = nullptr;
            m_size = 0;
        }
    }

    bool mmap_buffer::allocate(size_t length,int fd, size_t offset) {
        if (m_mem) {
            LOG_ERROR("mmap_buffer::alloc already allocated");
            return false;
        }
        auto mem = mmap(0 /* start anywhere */ ,
                          length, PROT_READ | PROT_WRITE, MAP_SHARED, fd,
                          offset);
        if(mem == MAP_FAILED) { 
            LOG_ERROR("mmap_buffer::alloc mmap failed");
            return false;
        }
        m_mem = mem;
        m_size = length;
        return true;
    }

}