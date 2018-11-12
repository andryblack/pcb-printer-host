#include "frame.h"
#include <cstdlib>
#include <new>
#include <cassert>
#include "video_source.h"

static Mutex g_frame_mutex;

Frame::Frame(VideoSource* source,size_t size) : m_source(source),m_capacity(size),m_size(0){}

FrameRef Frame::alloc(VideoSource* source,size_t size) {
	void* self_data = malloc(sizeof(Frame)+size);
	Frame* self = new(self_data) Frame(source,size);
	return FrameRef(self);
}
void Frame::write(const void* data,size_t size,struct timeval timestamp) {
	memcpy(static_cast<void*>(this+1),data,size);
	m_size = size;
	m_timestamp = timestamp;
}
void Frame::on_release() {
	if (m_source) {
		m_source->frame_release(this);
	} else {
		dealloc();
	}
}
void Frame::dealloc() {
	Frame* self = this;
	self->~Frame();
	free(self);
}
void Frame::add_ref() {
	MutexLock lock(g_frame_mutex);
	RefCounter::add_ref();
}
void Frame::remove_ref() {
	MutexLock lock(g_frame_mutex);
	RefCounter::remove_ref();
}
