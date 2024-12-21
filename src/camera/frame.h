#ifndef _CAMERA_FRAME_H_INCLUDED_
#define _CAMERA_FRAME_H_INCLUDED_

#include <common/intrusive_ptr.h>
#include <meta/object.h>
#include <sys/time.h>
#include <uv/mutex.h>

class Frame;
typedef common::intrusive_ptr<Frame> FramePtr;
class VideoSource;

class Frame : public meta::object {
	META_OBJECT
private:
	VideoSource* m_source;
	size_t m_capacity;
	size_t m_size;
	struct timeval m_timestamp;
	explicit Frame(VideoSource* source,size_t cap);
public:
	static FramePtr alloc(
		VideoSource* source,
		size_t size);
	void write(const void* data,size_t size,struct timeval m_timestamp);
	void dealloc();
	const void* get_data() const { return this + 1;};
	size_t get_size() const { return m_size; }
	struct timeval get_timestamp() const { return m_timestamp; }
	virtual void on_release();

	void add_ref();
	void remove_ref();
	
};


#endif /*_CAMERA_FRAME_H_INCLUDED_*/
