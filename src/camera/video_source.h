#ifndef _CAMERA_VIDEO_SOURCE_H_INCLUDED_
#define _CAMERA_VIDEO_SOURCE_H_INCLUDED_

#include "ref_counter.h"
#include "mutex.h"
#include <vector>
#include "frame.h"

class SendStream;

class VideoSource : public RefCounter {
private:
	Mutex m_frames_mutex;
	std::vector<Frame*> m_used_frames;
	std::vector<Frame*> m_free_frames;

	FrameRef get_frame(size_t size);
	Mutex m_frame_mutex;
	FrameRef	m_last_frame;
	void put_back( Frame* frame);
protected:
	volatile bool m_need_frame;
public:
	VideoSource();
	~VideoSource();

	void frame_release(Frame* frame);
	void put_frame(const void* data,size_t size,struct timeval timestamp);

	void register_stream(SendStream* stream);
	void unregister_stream(SendStream* stream);

	FrameRef get_frame();

	void push(lua_State* L);

	virtual void start() {}
	virtual void stop() {}

	virtual bool open(lua_State*) = 0;
	virtual void close() {}

	static int lnew(lua_State* L);
	static int lbind(lua_State* L);
	static int get_lframe(lua_State* L);
};
typedef Ref<VideoSource> VideoSourceRef;

#endif /*_CAMERA_VIDEO_SOURCE_H_INCLUDED_*/
