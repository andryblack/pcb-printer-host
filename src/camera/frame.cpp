#include "frame.h"
#include <cstdlib>
#include <new>
#include <cassert>
#include "video_source.h"

static uv::mutex g_frame_mutex;

META_OBJECT_INFO(Frame,meta::object)

Frame::Frame(VideoSource* source,size_t size) : m_source(source),m_capacity(size),m_size(0){}

FramePtr Frame::alloc(VideoSource* source,size_t size) {
	void* self_data = malloc(sizeof(Frame)+size);
	Frame* self = new(self_data) Frame(source,size);
	return FramePtr(self);
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
	uv::scoped_lock lock(g_frame_mutex);
	common::ref_counter_base::add_ref();
}
void Frame::remove_ref() {
	uv::scoped_lock lock(g_frame_mutex);
	common::ref_counter_base::remove_ref();
}
