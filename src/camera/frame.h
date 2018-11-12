#ifndef _CAMERA_FRAME_H_INCLUDED_
#define _CAMERA_FRAME_H_INCLUDED_

#include "ref_counter.h"
#include <sys/time.h>
#include "mutex.h"

class Frame;
typedef Ref<Frame> FrameRef;
class VideoSource;

class Frame : public RefCounter {
private:
	VideoSource* m_source;
	size_t m_capacity;
	size_t m_size;
	struct timeval m_timestamp;
	explicit Frame(VideoSource* source,size_t cap);
public:
	static FrameRef alloc(
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
