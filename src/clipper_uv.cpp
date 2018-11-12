#include "clipper_uv.h"

#include "luabind.h"

#include "llae.h"
#include "clipper_uv.h"

#ifndef CLIPPERLIB_MODNAME
#define CLIPPERLIB_MODNAME   "clipperlib"
#endif

#ifndef CLIPPERLIB_VERSION
#define CLIPPERLIB_VERSION   CLIPPER_VERSION
#endif

static const char* Path_mt = "clipperlib.Path";

ClipperPath::ClipperPath() {

}

ClipperPath::~ClipperPath() {

}

int ClipperPath::lnew(lua_State* L) {
	(new ClipperPath())->push(L);
	return 1;
}

void ClipperPath::push(lua_State* L) {
	new (lua_newuserdata(L,sizeof(ClipperPathRef))) ClipperPathRef(this);
	luaL_setmetatable(L,Path_mt);
}
void ClipperPath::clear(lua_State* L) {
	clipperlib::Path tmp;
	m_path.swap(tmp);
}
void ClipperPath::add_point(lua_State* L,lua_Integer x,lua_Integer y) {
	m_path.push_back(clipperlib::Point64(x,y));
}

int ClipperPath::get_point(lua_State* L) {
	ClipperPath* self = ClipperPathRef::get_ptr(L,1);
	lua_Integer idx = luaL_checkinteger(L,2);
	if (idx < 0 || idx >= self->m_path.size()) {
		luaL_error(L,"invalid index %d (size:%d)",idx,lua_Integer(self->m_path.size()));
	}
	const clipperlib::Point64& pnt(self->m_path[idx]);
	lua_pushinteger(L,pnt.x);
	lua_pushinteger(L,pnt.y);
	return 2;
}

int ClipperPath::import(lua_State* L) {
	luaL_checktype(L,1,LUA_TTABLE);
	lua_Integer plen = luaL_len(L,1);
	lua_Number scale = luaL_optnumber(L,2,1.0);
	ClipperPath* self = new ClipperPath();
	self->push(L);
	self->m_path.reserve(plen);
	for (lua_Integer i=1;i<=plen;++i) {
		lua_geti(L,1,i);
		luaL_checktype(L,-1,LUA_TTABLE);
		lua_geti(L,-1,1);
		lua_geti(L,-2,2);
		lua_Number x = lua_tonumber(L,-2);
		lua_Number y = lua_tonumber(L,-1);
		lua_pop(L,3);
		self->m_path.push_back(clipperlib::Point64(x*scale,y*scale));
	}
	return 1;
}

int ClipperPath::do_export(lua_State* L) {
	ClipperPath* self = ClipperPathRef::get_ptr(L,1);
	lua_Number s = luaL_optnumber(L,2,1.0);
	lua_createtable(L,self->m_path.size(),0);
	lua_Integer i = 1;
	for (clipperlib::Path::const_iterator it=self->m_path.begin();it!=self->m_path.end();++it) {
		lua_createtable(L,2,0);
		lua_pushnumber(L,it->x*s);
		lua_seti(L,-2,1);
		lua_pushnumber(L,it->y*s);
		lua_seti(L,-2,2);
		lua_seti(L,-2,i);
		++i;
	}
	return 1;
}

static inline const int64_t sq_len(const clipperlib::Point64& a, const clipperlib::Point64& b) {
	int64_t dx = a.x - b.x;
	int64_t dy = a.y - b.y;
	return dx * dx + dy * dy;
}

int ClipperPath::nearest_point(lua_State* L) {
	ClipperPath* self = ClipperPathRef::get_ptr(L,1);
	lua_Integer x = luaL_checkinteger(L,2);
	lua_Integer y = luaL_checkinteger(L,3);
	size_t size = self->m_path.size();
	if (size == 0) {
		luaL_error(L,"path is empty");
	}
	clipperlib::Point64 pnt(x,y);

	int64_t min_len = sq_len(pnt,self->m_path[0]);
	size_t min_idx = 0;
	for (size_t i=1;i<size;++i) {
		int64_t sl = sq_len(pnt,self->m_path[i]);
		if (sl < min_len) {
			min_len = sl;
			min_idx = i;
		}
	}
	lua_pushinteger(L,min_idx);
	lua_pushinteger(L,min_len);
	return 2;
}



static void lua_pushPaths(lua_State* L, clipperlib::Paths& paths) {
	lua_createtable(L,paths.size(),0);
	lua_Integer i = 1;
	for (clipperlib::Paths::iterator it = paths.begin();it!=paths.end();++it) {
		clipperlib::Path& p(*it);
		ClipperPath* r = new ClipperPath();
		r->swap(p);
		r->push(L);
		lua_seti(L,-2,i);
		++i;
	}
}

static const char* Clipper_mt = "clipperlib.Clipper";

Clipper::Clipper() {

}

Clipper::~Clipper() {

}

int Clipper::lnew(lua_State* L) {
	(new Clipper())->push(L);
	return 1;
}

void Clipper::push(lua_State* L) {
	new (lua_newuserdata(L,sizeof(ClipperRef))) ClipperRef(this);
	luaL_setmetatable(L,Clipper_mt);
}

void Clipper::clear(lua_State* L) {
	m_clipper.Clear();
}

void Clipper::add_path(lua_State* L,const ClipperPathRef& path) {
	clipperlib::PathType polytype = static_cast<clipperlib::PathType>(luaL_checkinteger(L,3));
	bool is_open = lua_toboolean(L,4);
	m_clipper.AddPath(path->get(),polytype,is_open);
}
int Clipper::add_paths(lua_State* L) {
	ClipperRef self = ClipperRef::get_ref(L,1);
	luaL_checktype(L,2,LUA_TTABLE);
	clipperlib::PathType polytype = static_cast<clipperlib::PathType>(luaL_checkinteger(L,3));
	bool is_open = lua_toboolean(L,4);
	lua_Integer plen = luaL_len(L,2);
	for (lua_Integer p=1;p<=plen;++p) {
		lua_geti(L,2,p);
		ClipperPathRef path = ClipperPathRef::get_ref(L,-1);
		self->m_clipper.AddPath(path->get(),polytype,is_open);
		lua_pop(L,1);
	}
	return 0;
}

int ClipperExecuteReq::start(lua_State* L) {
	m_clipper = ClipperRef::get_ref(L,1);
	m_type = static_cast<clipperlib::ClipType>(luaL_checkinteger(L,2));
	m_fr = static_cast<clipperlib::FillRule>(luaL_checkinteger(L,3));
	lua_pushthread(L);
	return ThreadWorkReq::start(L);
}

void ClipperExecuteReq::on_work() {
	m_result = m_clipper->get().Execute(m_type,m_solution_closed,m_solution_opened,m_fr);
}

void ClipperExecuteReq::on_after_work(int status) {
	if (status != 0) {
		ThreadWorkReq::on_after_work(status);
		return;
	}
	int res = 1;
	lua_State* L = llae_get_vm(m_work.loop);
	if (L) {
		if (m_th) {
			lua_pushboolean(L,m_result ? 1 : 0);
			if (m_result) {
				lua_pushPaths(L,m_solution_closed);
				lua_pushPaths(L,m_solution_opened);
				res = 3;
			}
			m_th.resumevi(L,"ClipperExecuteReq::on_after_work",res);
			m_th.reset(L);
		}
		
	}
}

int Clipper::execute(lua_State* L) {
	if (lua_isyieldable(L)) {
		{
			ClipperExecuteReqRef req(new ClipperExecuteReq());
			int res = req->start(L);
			lua_llae_handle_error(L,"clipper::execute",res);
		}
		return lua_yield(L,3);
	} 

	ClipperRef clipper = ClipperRef::get_ref(L,1);
	clipperlib::ClipType type = static_cast<clipperlib::ClipType>(luaL_checkinteger(L,2));
	clipperlib::FillRule fr = static_cast<clipperlib::FillRule>(luaL_checkinteger(L,3));
	clipperlib::Paths solution_closed;
	clipperlib::Paths solution_opened;
	bool r = clipper->m_clipper.Execute(type,solution_closed,solution_opened,fr);
	if (!r) {
		lua_pushboolean(L,0);
		lua_pushinteger(L,r);
		return 2;
	} 
	lua_pushboolean(L,1);
	lua_pushPaths(L,solution_closed);
	lua_pushPaths(L,solution_opened);
	return 3;
}

static const char* ClipperOffset_mt = "clipperlib.ClipperOffset";

ClipperOffset::ClipperOffset() {

}

ClipperOffset::~ClipperOffset() {

}

int ClipperOffset::lnew(lua_State* L) {
	(new ClipperOffset())->push(L);
	return 1;
}
void ClipperOffset::push(lua_State* L) {
	new (lua_newuserdata(L,sizeof(ClipperOffsetRef))) ClipperOffsetRef(this);
	luaL_setmetatable(L,ClipperOffset_mt);
}
void ClipperOffset::clear(lua_State* L) {
	m_clipper.Clear();
}
void ClipperOffset::add_path(lua_State* L,const ClipperPathRef& path) {
	clipperlib::JoinType jt = static_cast<clipperlib::JoinType>(luaL_checkinteger(L,3));
	clipperlib::EndType et = static_cast<clipperlib::EndType>(luaL_checkinteger(L,4));
	m_clipper.AddPath(path->get(),jt,et);
}

int ClipperOffset::add_paths(lua_State* L) {
	ClipperOffsetRef self = ClipperOffsetRef::get_ref(L,1);
	luaL_checktype(L,2,LUA_TTABLE);
	clipperlib::JoinType jt = static_cast<clipperlib::JoinType>(luaL_checkinteger(L,3));
	clipperlib::EndType et = static_cast<clipperlib::EndType>(luaL_checkinteger(L,4));
	lua_Integer plen = luaL_len(L,2);
	for (lua_Integer p=1;p<=plen;++p) {
		lua_geti(L,2,p);
		ClipperPathRef path = ClipperPathRef::get_ref(L,-1);
		self->get().AddPath(path->get(),jt,et);
		lua_pop(L,1);
	}
	return 0;
}

int ClipperOffsetExecuteReq::start(lua_State* L) {
	m_clipper = ClipperOffsetRef::get_ref(L,1);
	m_delta = luaL_checknumber(L,2);
	lua_pushthread(L);
	return ThreadWorkReq::start(L);
}

void ClipperOffsetExecuteReq::on_work() {
	m_clipper->get().Execute(m_solution,m_delta);
}

void ClipperOffsetExecuteReq::on_after_work(int status) {
	if (status != 0) {
		ThreadWorkReq::on_after_work(status);
		return;
	}
	lua_State* L = llae_get_vm(m_work.loop);
	if (L) {
		if (m_th) {
			lua_pushPaths(L,m_solution);
			m_th.resumevi(L,"ClipperOffsetExecuteReq::on_after_work",1);
			m_th.reset(L);
		}
	}
}

int ClipperOffset::execute(lua_State* L) {
	if (lua_isyieldable(L)) {
		{
			ClipperOffsetExecuteReqRef req(new ClipperOffsetExecuteReq());
			int res = req->start(L);
			lua_llae_handle_error(L,"clipperoffset::execute",res);
		}
		return lua_yield(L,2);
	} 
	ClipperOffsetRef clipper = ClipperOffsetRef::get_ref(L,1);
	double delta = luaL_checknumber(L,2);
	clipperlib::Paths solution;
	clipper->get().Execute(solution,delta);
	lua_pushPaths(L,solution);
	return 1;
}

static int lua_clipperlib_new(lua_State *L) {
	lua_newtable(L);

	luaL_newmetatable(L,Path_mt);
	luabind::bind(L,"new",&ClipperPath::lnew);
	luabind::bind(L,"clear",&ClipperPath::clear);
	luabind::bind(L,"size",&ClipperPath::size);
	luabind::bind(L,"add_point",&ClipperPath::add_point);
	luabind::bind(L,"get_point",&ClipperPath::get_point);
	luabind::bind(L,"import",&ClipperPath::import);
	luabind::bind(L,"export",&ClipperPath::do_export);
	luabind::bind(L,"nearest_point",&ClipperPath::nearest_point);
    lua_pushvalue(L,-1);
    lua_setfield(L,-2,"__index");
    lua_pushcfunction(L,&ClipperPathRef::gc);
	lua_setfield(L,-2,"__gc");
    lua_setfield(L,-2,"Path");

	luaL_newmetatable(L,Clipper_mt);
	luabind::bind(L,"new",&Clipper::lnew);
	luabind::bind(L,"clear",&Clipper::clear);
	luabind::bind(L,"add_path",&Clipper::add_path);
	luabind::bind(L,"add_paths",&Clipper::add_paths);
	luabind::bind(L,"execute",&Clipper::execute);

    lua_pushvalue(L,-1);
    lua_setfield(L,-2,"__index");
    lua_pushcfunction(L,&ClipperRef::gc);
	lua_setfield(L,-2,"__gc");
    lua_setfield(L,-2,"Clipper");

    luaL_newmetatable(L,ClipperOffset_mt);
    luabind::bind(L,"new",&ClipperOffset::lnew);
	luabind::bind(L,"clear",&ClipperOffset::clear);
	luabind::bind(L,"add_path",&ClipperOffset::add_path);
	luabind::bind(L,"add_paths",&ClipperOffset::add_paths);
	luabind::bind(L,"execute",&ClipperOffset::execute);

    lua_pushvalue(L,-1);
    lua_setfield(L,-2,"__index");
    lua_pushcfunction(L,&ClipperOffsetRef::gc);
	lua_setfield(L,-2,"__gc");
    lua_setfield(L,-2,"ClipperOffset");

    lua_newtable(L);
    lua_pushinteger(L,clipperlib::ctNone);
    lua_setfield(L,-2,"None");
    lua_pushinteger(L,clipperlib::ctIntersection);
    lua_setfield(L,-2,"Intersection");
    lua_pushinteger(L,clipperlib::ctUnion);
    lua_setfield(L,-2,"Union");
    lua_pushinteger(L,clipperlib::ctDifference);
    lua_setfield(L,-2,"Difference");
    lua_pushinteger(L,clipperlib::ctXor);
    lua_setfield(L,-2,"Xor");
    lua_setfield(L,-2,"ClipType");

    lua_newtable(L);
    lua_pushinteger(L,clipperlib::ptSubject);
    lua_setfield(L,-2,"Subject");
    lua_pushinteger(L,clipperlib::ptClip);
    lua_setfield(L,-2,"Clip");
    lua_setfield(L,-2,"PathType");

    lua_newtable(L);
    lua_pushinteger(L,clipperlib::frEvenOdd);
    lua_setfield(L,-2,"EvenOdd");
    lua_pushinteger(L,clipperlib::frNonZero);
    lua_setfield(L,-2,"NonZero");
    lua_pushinteger(L,clipperlib::frPositive);
    lua_setfield(L,-2,"Positive");
    lua_pushinteger(L,clipperlib::frNegative);
    lua_setfield(L,-2,"Negative");
    lua_setfield(L,-2,"FillRule");

    lua_newtable(L);
    lua_pushinteger(L,clipperlib::kSquare);
    lua_setfield(L,-2,"Square");
    lua_pushinteger(L,clipperlib::kRound);
    lua_setfield(L,-2,"Round");
    lua_pushinteger(L,clipperlib::kMiter);
    lua_setfield(L,-2,"Miter");
    lua_setfield(L,-2,"JoinType");

    lua_newtable(L);
    lua_pushinteger(L,clipperlib::kPolygon);
    lua_setfield(L,-2,"Polygon");
    lua_pushinteger(L,clipperlib::kOpenJoined);
    lua_setfield(L,-2,"OpenJoined");
    lua_pushinteger(L,clipperlib::kOpenButt);
    lua_setfield(L,-2,"OpenButt");
    lua_pushinteger(L,clipperlib::kOpenSquare);
    lua_setfield(L,-2,"OpenSquare");
    lua_pushinteger(L,clipperlib::kOpenRound);
    lua_setfield(L,-2,"OpenRound");
    lua_setfield(L,-2,"EndType");

	/* Set module name / version fields */
    lua_pushliteral(L, CLIPPERLIB_MODNAME);
    lua_setfield(L, -2, "_NAME");
    lua_pushliteral(L, CLIPPERLIB_VERSION);
    lua_setfield(L, -2, "_VERSION");
    return 1;
}

extern "C" int luaopen_clipperlib(lua_State* L) {
	lua_clipperlib_new(L);
	return 1;
}
