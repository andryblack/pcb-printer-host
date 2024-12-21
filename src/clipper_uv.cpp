#include "clipper_uv.h"
#include <lua/bind.h>
#include <lua/stack.h>
#include <uv/work.h>
#include <uv/luv.h>

META_OBJECT_INFO(ClipperPath,meta::object)
META_OBJECT_INFO(Clipper,meta::object)
META_OBJECT_INFO(ClipperOffset,meta::object)

ClipperPath::ClipperPath() {
	
}

ClipperPath::~ClipperPath() {

}

void ClipperPath::lbind(lua::state& l) {
	lua::bind::function(l,"new",&ClipperPath::lnew);
	lua::bind::function(l,"clear",&ClipperPath::clear);
	lua::bind::function(l,"size",&ClipperPath::size);
	lua::bind::function(l,"add_point",&ClipperPath::add_point);
	lua::bind::function(l,"get_point",&ClipperPath::get_point);
	lua::bind::function(l,"import",&ClipperPath::import);
	lua::bind::function(l,"export",&ClipperPath::do_export);
	lua::bind::function(l,"nearest_point",&ClipperPath::nearest_point);
	lua::bind::function(l,"__tostring",&ClipperPath::_tostring);
}

lua::multiret ClipperPath::lnew(lua::state& l) {
	lua::push(l,ClipperPathPtr(new ClipperPath()));
	return {1};
}

void ClipperPath::clear() {
	clipperlib::Path tmp;
	m_path.swap(tmp);
}

lua::multiret ClipperPath::_tostring(lua::state& l) {
	l.checkstack(m_path.size());
	l.checkstack(5);
	for (auto& pnt:m_path) {
		l.pushstring("{");
		l.pushinteger(pnt.x);
		l.pushstring(",");
		l.pushinteger(pnt.y);
		l.pushstring("},");
		l.concat(5);
	}
	if (!m_path.empty()) {
		l.concat(m_path.size());
		return {1};
	}
	l.pushstring("");
	return {1};
}

void ClipperPath::add_point(lua_Integer x,lua_Integer y) {
	m_path.push_back(clipperlib::Point64(x,y));
}

lua::multiret ClipperPath::get_point(lua::state& l,lua_Integer idx) {
	if (idx < 0 || idx >= m_path.size()) {
		l.error("invalid index %d (size:%d)",idx,lua_Integer(m_path.size()));
	}
	const clipperlib::Point64& pnt(m_path[idx]);
	l.pushinteger(pnt.x);
	l.pushinteger(pnt.y);
	return {2};
}

lua::multiret ClipperPath::import(lua::state& l) {
	l.checktype(1,lua::value_type::table);
	lua_Integer plen = l.len(1);
	lua_Number scale = l.optnumber(2,1.0);
	ClipperPath* self = new ClipperPath();
	lua::push(l,ClipperPathPtr(self));
	self->m_path.reserve(plen);
	for (lua_Integer i=1;i<=plen;++i) {
		l.geti(1,i);
		l.checktype(-1,lua::value_type::table);
		l.geti(-1,1);
		l.geti(-2,2);
		lua_Number x = l.tonumber(-2);
		lua_Number y = l.tonumber(-1);
		l.pop(3);
		self->m_path.push_back(clipperlib::Point64(x*scale,y*scale));
	}
	return {1};
}

lua::multiret ClipperPath::do_export(lua::state& l) {
	lua_Number s = l.optnumber(2,1.0);
	l.createtable(m_path.size(),0);
	lua_Integer i = 1;
	for (auto it=m_path.begin();it!=m_path.end();++it) {
		l.createtable(2,0);
		l.pushnumber(it->x*s);
		l.seti(-2,1);
		l.pushnumber(it->y*s);
		l.seti(-2,2);
		l.seti(-2,i);
		++i;
	}
	return {1};
}

static inline const int64_t sq_len(const clipperlib::Point64& a, const clipperlib::Point64& b) {
	int64_t dx = a.x - b.x;
	int64_t dy = a.y - b.y;
	return dx * dx + dy * dy;
}

lua::multiret ClipperPath::nearest_point(lua::state& l) {
	lua_Integer x = l.checkinteger(2);
	lua_Integer y = l.checkinteger(3);
	size_t size = m_path.size();
	if (size == 0) {
		l.error("path is empty");
	}
	clipperlib::Point64 pnt(x,y);

	int64_t min_len = sq_len(pnt,m_path[0]);
	size_t min_idx = 0;
	for (size_t i=1;i<size;++i) {
		int64_t sl = sq_len(pnt,m_path[i]);
		if (sl < min_len) {
			min_len = sl;
			min_idx = i;
		}
	}
	l.pushinteger(min_idx);
	l.pushinteger(min_len);
	return {2};
}



static void lua_pushPaths(lua::state& l, clipperlib::Paths& paths) {
	l.createtable(paths.size(),0);
	lua_Integer i = 1;
	for (clipperlib::Paths::iterator it = paths.begin();it!=paths.end();++it) {
		clipperlib::Path& p(*it);
		ClipperPath* r = new ClipperPath();
		r->swap(p);
		lua::push(l,ClipperPathPtr(r));
		l.seti(-2,i);
		++i;
	}
}


Clipper::Clipper() {

}

Clipper::~Clipper() {

}

void Clipper::lbind(lua::state& l) {
	lua::bind::function(l,"new",&Clipper::lnew);
	lua::bind::function(l,"clear",&Clipper::clear);
	lua::bind::function(l,"add_path",&Clipper::add_path);
	lua::bind::function(l,"add_paths",&Clipper::add_paths);
	lua::bind::function(l,"execute",&Clipper::execute);
}

lua::multiret Clipper::lnew(lua::state& l) {
	lua::push(l,ClipperPtr(new Clipper()));
	return {1};
}


void Clipper::clear() {
	m_clipper.Clear();
}

void Clipper::add_path(lua::state& l,const ClipperPathPtr& path) {
	clipperlib::PathType polytype = static_cast<clipperlib::PathType>(l.checkinteger(3));
	bool is_open = l.toboolean(4);
	m_clipper.AddPath(path->get(),polytype,is_open);
}

void Clipper::add_paths(lua::state& l) {
	l.checktype(2,lua::value_type::table);
	clipperlib::PathType polytype = static_cast<clipperlib::PathType>(l.checkinteger(3));
	bool is_open = l.toboolean(4);
	lua_Integer plen = l.len(2);
	for (lua_Integer p=1;p<=plen;++p) {
		l.geti(2,p);
		auto path = lua::stack<ClipperPathPtr>::get(l,-1);
		m_clipper.AddPath(path->get(),polytype,is_open);
		l.pop(1);
	}
}

class ClipperExecuteReq : public uv::lua_cont_work {
private:
	ClipperPtr m_clipper;
	clipperlib::ClipType m_type;
	clipperlib::FillRule m_fr;
	clipperlib::Paths m_solution_closed;
	clipperlib::Paths m_solution_opened;
	bool m_result;
	virtual void on_work() override {
		m_result =  m_clipper->get().Execute(m_type,m_solution_closed,m_solution_opened,m_fr);
	}
	virtual int resume_args(lua::state& l,int status) override {
		if (status != 0) {
			l.pushnil();
            uv::push_error(l,status);
            return 2;
		}
		if (m_result) {
			lua_pushPaths(l,m_solution_closed);
			lua_pushPaths(l,m_solution_opened);
			return 2;
		}
		l.pushnil();
		l.pushstring("failed");
		return 2;
	}
public:
	ClipperExecuteReq( ClipperPtr&& clipper,clipperlib::ClipType ct,clipperlib::FillRule fr,lua::ref&& cont) : uv::lua_cont_work(std::move(cont)),
		m_clipper(std::move(clipper)),m_type(ct),m_fr(fr),m_result(false) {}

};

lua::multiret Clipper::execute(lua::state& l) {
	if (!l.isyieldable()) {
		l.error("Clipper::execute is async");
	}
	clipperlib::ClipType type = static_cast<clipperlib::ClipType>(l.checkinteger(2));
	clipperlib::FillRule fr = static_cast<clipperlib::FillRule>(l.checkinteger(3));
	{

		l.pushthread();
		lua::ref cont;
		cont.set(l);

		common::intrusive_ptr<ClipperExecuteReq> req(new ClipperExecuteReq(ClipperPtr(this),type,fr,std::move(cont)));

		int r = req->queue_work(l);
		if (r < 0) {
			req->reset(l);
			l.pushnil();
			uv::push_error(l,r);
			return {2};
		} 
	}
	l.yield(0);
	return {0};
}

ClipperOffset::ClipperOffset() {

}

ClipperOffset::~ClipperOffset() {

}

lua::multiret ClipperOffset::lnew(lua::state& l) {
	lua::push(l,ClipperOffsetPtr(new ClipperOffset()));
	return {1};
}

void ClipperOffset::lbind(lua::state& l) {
	lua::bind::function(l,"new",&ClipperOffset::lnew);
	lua::bind::function(l,"clear",&ClipperOffset::clear);
	lua::bind::function(l,"add_path",&ClipperOffset::add_path);
	lua::bind::function(l,"add_paths",&ClipperOffset::add_paths);
	lua::bind::function(l,"execute",&ClipperOffset::execute);
}

void ClipperOffset::clear() {
	m_clipper.Clear();
}

void ClipperOffset::add_path(lua::state& l,const ClipperPathPtr& path) {
	clipperlib::JoinType jt = static_cast<clipperlib::JoinType>(l.checkinteger(3));
	clipperlib::EndType et = static_cast<clipperlib::EndType>(l.checkinteger(4));
	m_clipper.AddPath(path->get(),jt,et);
}

void ClipperOffset::add_paths(lua::state& l) {
	l.checktype(2,lua::value_type::table);
	clipperlib::JoinType jt = static_cast<clipperlib::JoinType>(l.checkinteger(3));
	clipperlib::EndType et = static_cast<clipperlib::EndType>(l.checkinteger(4));
	lua_Integer plen = l.len(2);
	for (lua_Integer p=1;p<=plen;++p) {
		l.geti(2,p);
		auto path = lua::stack<ClipperPathPtr>::get(l,-1);
		m_clipper.AddPath(path->get(),jt,et);
		l.pop(1);
	}
}



class ClipperOffsetExecuteReq : public uv::lua_cont_work {
private:
	ClipperOffsetPtr m_clipper;
	double m_delta;
	clipperlib::Paths m_solution;
	virtual void on_work() override {
		m_clipper->get().Execute(m_solution,m_delta);
	}
	virtual int resume_args(lua::state& l,int status) override {
		if (status != 0) {
			l.pushnil();
            uv::push_error(l,status);
            return 2;
		}
		lua_pushPaths(l,m_solution);
		return 1;
	}
public:
	ClipperOffsetExecuteReq( ClipperOffsetPtr&& clipper,double delta,lua::ref&& cont) : uv::lua_cont_work(std::move(cont)),
		m_clipper(std::move(clipper)),m_delta(delta) {}

};

lua::multiret ClipperOffset::execute(lua::state& l) {
	if (!l.isyieldable()) {
		l.error("ClipperOffset::execute is async");
	}
	auto offset = l.checknumber(2);
	{

		l.pushthread();
		lua::ref cont;
		cont.set(l);

		common::intrusive_ptr<ClipperOffsetExecuteReq> req{new ClipperOffsetExecuteReq(ClipperOffsetPtr(this),offset,std::move(cont))};

		int r = req->queue_work(l);
		if (r < 0) {
			req->reset(l);
			l.pushnil();
			uv::push_error(l,r);
			return {2};
		} 
	}
	l.yield(0);
	return {0};
}


int luaopen_clipperlib(lua_State* L) {
	lua::state l(L);
	lua::bind::object<ClipperPath>::register_metatable(l,&ClipperPath::lbind);
	lua::bind::object<Clipper>::register_metatable(l,&Clipper::lbind);
	lua::bind::object<ClipperOffset>::register_metatable(l,&ClipperOffset::lbind);
	l.createtable();

	lua::bind::object<ClipperPath>::get_metatable(l);
	l.setfield(-2,"Path");
	lua::bind::object<Clipper>::get_metatable(l);
	l.setfield(-2,"Clipper");
	lua::bind::object<ClipperOffset>::get_metatable(l);
	l.setfield(-2,"ClipperOffset");


	l.createtable();
	lua::bind::value(l,"None",clipperlib::ctNone);
    lua::bind::value(l,"Intersection",clipperlib::ctIntersection);
    lua::bind::value(l,"Union",clipperlib::ctUnion);
    lua::bind::value(l,"Difference",clipperlib::ctDifference);
    lua::bind::value(l,"Xor",clipperlib::ctXor);
    l.setfield(-2,"ClipType");

	l.createtable();
	lua::bind::value(l,"Subject",clipperlib::ptSubject);
    lua::bind::value(l,"Clip",clipperlib::ptClip);
    l.setfield(-2,"PathType");

	l.createtable();
	lua::bind::value(l,"EvenOdd",clipperlib::frEvenOdd);
    lua::bind::value(l,"NonZero",clipperlib::frNonZero);
   	lua::bind::value(l,"Positive",clipperlib::frPositive);
   	lua::bind::value(l,"Negative",clipperlib::frNegative);
    l.setfield(-2,"FillRule");

	l.createtable();
	lua::bind::value(l,"Square",clipperlib::kSquare);
    lua::bind::value(l,"Round",clipperlib::kRound);
   	lua::bind::value(l,"Miter",clipperlib::kMiter);
    l.setfield(-2,"JoinType");

	l.createtable();
	lua::bind::value(l,"Polygon",clipperlib::kPolygon);
    lua::bind::value(l,"OpenJoined",clipperlib::kOpenJoined);
   	lua::bind::value(l,"OpenButt",clipperlib::kOpenButt);
    lua::bind::value(l,"OpenSquare",clipperlib::kOpenSquare);
    lua::bind::value(l,"OpenRound",clipperlib::kOpenRound);
    l.setfield(-2,"EndType");
	return 1;
}
