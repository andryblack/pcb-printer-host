#ifndef _CAMERA_VIDEO_SOURCE_H_INCLUDED_
#define _CAMERA_VIDEO_SOURCE_H_INCLUDED_

#include <meta/object.h>
#include <uv/mutex.h>
#include <lua/state.h>
#include <common/intrusive_ptr.h>
#include <vector>
#include "frame.h"

class SendStream;

class VideoSource : public meta::object {
	META_OBJECT
private:
	uv::mutex m_frames_mutex;
	std::vector<Frame*> m_used_frames;
	std::vector<Frame*> m_free_frames;

	FramePtr get_frame(size_t size);
	uv::mutex m_frame_mutex;
	FramePtr	m_last_frame;
	void put_back( Frame* frame);


protected:
	static lua::multiret push(lua::state& l,VideoSource* self);
	volatile bool m_need_frame;
public:
	VideoSource();
	~VideoSource();

	void frame_release(Frame* frame);
	void put_frame(const void* data,size_t size,struct timeval timestamp);

	void register_stream(SendStream* stream);
	void unregister_stream(SendStream* stream);

	FramePtr get_frame();


	virtual void start() {}
	virtual void stop() {}

	virtual bool open(lua::state& l) = 0;
	virtual void close() {}

	static lua::multiret lnew(lua::state& l);
	static void lbind(lua::state& l);
	lua::multiret get_lframe(lua::state& l);
};
typedef common::intrusive_ptr<VideoSource> VideoSourcePtr;

#endif /*_CAMERA_VIDEO_SOURCE_H_INCLUDED_*/
