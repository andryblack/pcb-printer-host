#pragma once

#include <cstring>

namespace V4L {

    class mmap_buffer {
    private:
        void* m_mem = nullptr;
        size_t m_size = 0;
    public:
        mmap_buffer() {}
        ~mmap_buffer();
        mmap_buffer(mmap_buffer&& o);
        mmap_buffer(const mmap_buffer&) = delete;
        void release();
        void* get_mem() { return m_mem; }
        size_t get_size() { return m_size; }
        
        bool allocate(size_t length,int fd, size_t offset);
    };

}