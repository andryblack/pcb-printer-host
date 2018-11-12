#include "video_source.h"
#include <algorithm>
#include <cassert>
#include "luabind.h"

static const size_t POOL_SIZE = 16;
static const char* VideoSource_mt = "Camera.VideoSource";

VideoSource::VideoSource() : m_need_frame(true) {

}

VideoSource::~VideoSource() {

}

// from rendering threads
FrameRef VideoSource::get_frame(size_t size) {
	Frame* res_frame = 0;
	{
		MutexLock lock(m_frames_mutex);
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
		return FrameRef(res_frame);
	}
	FrameRef res = Frame::alloc(this,size);
	{
		MutexLock lock(m_frames_mutex);
		m_used_frames.push_back(res.get());
	}
	return res;
}

// from any thread
void VideoSource::frame_release(Frame* frame) {
	MutexLock lock(m_frames_mutex);
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
	FrameRef new_frame = get_frame(size);
	new_frame->write(data,size,timestamp);
	{
		MutexLock lock(m_frame_mutex);
		m_last_frame = new_frame;
		m_need_frame = false;
	}
}
// from main thread
FrameRef VideoSource::get_frame() {
	MutexLock lock(m_frame_mutex);
	FrameRef res = m_last_frame;
	m_need_frame = true;
	return res;
}

int VideoSource::get_lframe(lua_State* L) {
	VideoSource* self = VideoSourceRef::get_ptr(L,1);
	FrameRef frame = self->get_frame();
	if (!frame) {
		lua_pushnil(L);
	} else {
		lua_pushlstring(L,static_cast<const char *>(frame->get_data()),frame->get_size());
	}
	return 1;
}

void VideoSource::push(lua_State* L) {
	new (lua_newuserdata(L,sizeof(VideoSourceRef))) VideoSourceRef(this);
	luaL_setmetatable(L,VideoSource_mt);
}

int VideoSource::lbind(lua_State* L) {
	luaL_newmetatable(L,VideoSource_mt);
	lua_newtable(L);
	luabind::bind(L,"open",&VideoSource::open);
	luabind::bind(L,"close",&VideoSource::close);
	luabind::bind(L,"start",&VideoSource::start);
	luabind::bind(L,"stop",&VideoSource::stop);
	luabind::bind(L,"get_frame",&VideoSource::get_lframe);
	lua_setfield(L,-2,"__index");
	lua_pushcfunction(L,&VideoSourceRef::gc);
	lua_setfield(L,-2,"__gc");
	lua_pop(L,1);
	return 0;
}
