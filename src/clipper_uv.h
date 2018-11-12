#ifndef _CLIPPER_UV_H_INCLUDED_
#define _CLIPPER_UV_H_INCLUDED_

#include "uv_req_holder.h"
#include "clipperlib/clipper.h"
#include "clipperlib/clipper_offset.h"
#include "lua_holder.h"
#include "work.h"

class ClipperPath: public RefCounter {
private:
	clipperlib::Path m_path;
public:
	ClipperPath();
	~ClipperPath();
	static int lnew(lua_State* L);
	void push(lua_State* L);
	void clear(lua_State* L);
	void add_point(lua_State* L,lua_Integer x,lua_Integer y);
	static int get_point(lua_State* L);
	static int import(lua_State* L);
	static int do_export(lua_State* L);
	static int nearest_point(lua_State* L);
	lua_Integer size(lua_State* L) { return m_path.size(); }
	void swap(clipperlib::Path& p) { m_path.swap(p); }
	clipperlib::Path& get() { return m_path; }
};
typedef Ref<ClipperPath> ClipperPathRef;

class Clipper : public RefCounter {
private:
	clipperlib::Clipper m_clipper;
public:
	Clipper();
	~Clipper();
	static int lnew(lua_State* L);
	void push(lua_State* L);

	void clear(lua_State* L);
	void add_path(lua_State* L,const ClipperPathRef& path);
	static int add_paths(lua_State* L);
	static int execute(lua_State* L);

	clipperlib::Clipper& get() { return m_clipper; }
};
typedef Ref<Clipper> ClipperRef;

class ClipperOffset : public RefCounter {
private:
	clipperlib::ClipperOffset m_clipper;
public:
	ClipperOffset();
	~ClipperOffset();

	static int lnew(lua_State* L);
	void push(lua_State* L);

	void clear(lua_State* L);
	void add_path(lua_State* L,const ClipperPathRef& path);
	static int add_paths(lua_State* L);
	static int execute(lua_State* L);

	clipperlib::ClipperOffset& get() { return m_clipper; }
};
typedef Ref<ClipperOffset> ClipperOffsetRef;


class ClipperExecuteReq : public ThreadWorkReq {
private:
	ClipperRef m_clipper;
	clipperlib::ClipType m_type;
	clipperlib::FillRule m_fr;
	clipperlib::Paths m_solution_closed;
	clipperlib::Paths m_solution_opened;
	bool m_result;
	virtual void on_work();
	virtual void on_after_work(int status);
public:
	int start(lua_State* L);
};
typedef Ref<ClipperExecuteReq> ClipperExecuteReqRef;


class ClipperOffsetExecuteReq : public ThreadWorkReq {
private:
	ClipperOffsetRef m_clipper;
	double m_delta;
	clipperlib::Paths m_solution;
	virtual void on_work();
	virtual void on_after_work(int status);
public:
	int start(lua_State* L);
};
typedef Ref<ClipperOffsetExecuteReq> ClipperOffsetExecuteReqRef;

#endif /*_CLIPPER_UV_H_INCLUDED_*/