#ifndef _SERIAL_H_INCLUDED_
#define _SERIAL_H_INCLUDED_

#include "stream.h"

class Serial : public UVHandleHolder {
	uv_poll_t m_poll;
	int m_fd;
	bool	m_need_stop;
	LuaThread m_th;
	static void poll_cb(uv_poll_t* poll,int status,int events);
	void on_poll(int status,int events);
	char m_buf[1024];
	virtual uv_handle_t* get_handle() {
		return reinterpret_cast<uv_handle_t*>(&m_poll);
	}
public:
	explicit Serial(uv_loop_t* loop,int fd);
	~Serial();
	bool configure_baud(lua_State* L,int baud);
	void start_read(lua_State* L,const luabind::function& f);
	void read(lua_State* L);
	void write(lua_State* L);
	void close(lua_State* L);
	void push(lua_State* L);
	void stop_read(lua_State* L);
	static int lopen(lua_State* L);
	static void lbind(lua_State* L);
};
typedef Ref<Serial> SerialRef;

#endif /*_SERIAL_H_INCLUDED_*/
