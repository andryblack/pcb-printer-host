#include "video_source.h"
#include <algorithm>
#include <cassert>
#include <lua/bind.h>

META_OBJECT_INFO(VideoSource,meta::object)

static const size_t POOL_SIZE = 16;

VideoSource::VideoSource() : m_need_frame(true) {

}

VideoSource::~VideoSource() {

}

// from rendering threads
FramePtr VideoSource::get_frame(size_t size) {
	Frame* res_frame = 0;
	{
		uv::scoped_lock lock(m_frames_mutex);
		for (std::vector<Frame*>::iterator it = m_free_frames.begin(); it != m_free_frames.end(); ++it) {
			if ((*it)->get_size() >= size) {
				res_frame = *it;
				m_free_frames.erase(it);
				m_used_frames.push_back(res_frame);
				break;
			}
		}
	}
	if (res_frame) {
		return FramePtr(res_frame);
	}
	FramePtr res = Frame::alloc(this,size);
	{
		uv::scoped_lock lock(m_frames_mutex);
		m_used_frames.push_back(res.get());
	}
	return res;
}

// from any thread
void VideoSource::frame_release(Frame* frame) {
	uv::scoped_lock lock(m_frames_mutex);
	std::vector<Frame*>::iterator it = std::find(m_used_frames.begin(),m_used_frames.end(),frame);
	assert(it != m_used_frames.end());
	m_used_frames.erase(it);
	m_free_frames.push_back(frame);
	if (m_free_frames.size() > POOL_SIZE) {
		Frame* erased = m_free_frames.front();
		m_free_frames.erase(m_free_frames.begin());
		erased->dealloc();
	}
}

// from rendering thread
void VideoSource::put_frame(const void* data,size_t size,struct timeval timestamp) {
	FramePtr new_frame = get_frame(size);
	new_frame->write(data,size,timestamp);
	{
		uv::scoped_lock lock(m_frame_mutex);
		m_last_frame = new_frame;
		m_need_frame = false;
	}
}
// from main thread
FramePtr VideoSource::get_frame() {
	uv::scoped_lock lock(m_frame_mutex);
	FramePtr res = m_last_frame;
	m_need_frame = true;
	return res;
}

lua::multiret VideoSource::get_lframe(lua::state& l) {
	FramePtr frame = get_frame();
	if (!frame) {
		l.pushnil();
	} else {
		l.pushlstring(static_cast<const char *>(frame->get_data()),frame->get_size());
	}
	return {1};
}


lua::multiret VideoSource::push(lua::state& l,VideoSource* self) {
	lua::push(l,VideoSourcePtr( self ));
	return {1};
}

void VideoSource::lbind(lua::state& l) {
	lua::bind::function(l,"new",&VideoSource::lnew);
	lua::bind::function(l,"open",&VideoSource::open);
	lua::bind::function(l,"close",&VideoSource::close);
	lua::bind::function(l,"start",&VideoSource::start);
	lua::bind::function(l,"stop",&VideoSource::stop);
	lua::bind::function(l,"get_frame",&VideoSource::get_lframe);
}

int luaopen_camera(lua_State* L)  {
	lua::state l(L);
	lua::bind::object<VideoSource>::register_metatable(l,&VideoSource::lbind);
	l.createtable();
	

	lua::bind::object<VideoSource>::get_metatable(l);
	l.setfield(-2,"VideoSource");
	return 1;
}