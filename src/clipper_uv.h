#ifndef _CLIPPER_UV_H_INCLUDED_
#define _CLIPPER_UV_H_INCLUDED_

#include <meta/object.h>
#include <common/intrusive_ptr.h>
#include <lua/state.h>
#include "clipperlib/clipper.h"
#include "clipperlib/clipper_offset.h"


class ClipperPath: public meta::object {
	META_OBJECT
private:
	clipperlib::Path m_path;
public:
	ClipperPath();
	~ClipperPath();
	static lua::multiret lnew(lua::state& l);
	static void lbind(lua::state& l);

	void clear();
	void add_point(lua_Integer x,lua_Integer y);
	lua::multiret get_point(lua::state& l,lua_Integer idx);
	static lua::multiret import(lua::state& l);
	lua::multiret do_export(lua::state& l);
	lua::multiret nearest_point(lua::state& l);
	lua_Integer size() const { return m_path.size(); }
	void swap(clipperlib::Path& p) { m_path.swap(p); }
	clipperlib::Path& get() { return m_path; }
	lua::multiret _tostring(lua::state& l);
};
typedef common::intrusive_ptr<ClipperPath> ClipperPathPtr;

class Clipper : public meta::object {
	META_OBJECT
private:
	clipperlib::Clipper m_clipper;
public:
	Clipper();
	~Clipper();
	static lua::multiret lnew(lua::state& l);
	static void lbind(lua::state& l);

	void clear();
	void add_path(lua::state& l,const ClipperPathPtr& path);
	void add_paths(lua::state& l);
	lua::multiret execute(lua::state& l);

	clipperlib::Clipper& get() { return m_clipper; }
};
typedef common::intrusive_ptr<Clipper> ClipperPtr;

class ClipperOffset : public meta::object {
	META_OBJECT
private:
	clipperlib::ClipperOffset m_clipper;
public:
	ClipperOffset();
	~ClipperOffset();

	static lua::multiret lnew(lua::state& l);
	static void lbind(lua::state& l);

	void clear();
	void add_path(lua::state& l,const ClipperPathPtr& path);
	void add_paths(lua::state& l);
	lua::multiret execute(lua::state& l);

	clipperlib::ClipperOffset& get() { return m_clipper; }
};
typedef common::intrusive_ptr<ClipperOffset> ClipperOffsetPtr;




#endif /*_CLIPPER_UV_H_INCLUDED_*/