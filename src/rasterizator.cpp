#include "rasterizator.h"
#include <algorithm>
#include <iostream>

static const char* Rasterizator_mt = "Rasterizator";

Rasterizator::Rasterizator() : m_x_scale(1.0),m_y_scale(1.0),m_bounds(INT64_MAX, INT64_MAX, INT64_MIN, INT64_MIN) {
	m_num_steps = 32;
}

void Rasterizator::push(lua_State* L) {
	new (lua_newuserdata(L,sizeof(RasterizatorRef))) RasterizatorRef(this);
	luaL_setmetatable(L,Rasterizator_mt);
}
int Rasterizator::lnew(lua_State* L) {
	(new Rasterizator())->push(L);
	return 1;
}
int Rasterizator::add_paths(lua_State* L) {
	RasterizatorRef self = RasterizatorRef::get_ref(L,1);
	luaL_checktype(L,2,LUA_TTABLE);
	lua_Integer len = luaL_len(L,2);
	self->m_paths.reserve(self->m_paths.size()+len);
	for (lua_Integer p=1;p<=len;++p) {
		lua_geti(L,2,p);
		
		self->m_paths.push_back(clipperlib::Path());
		clipperlib::Path& path(self->m_paths.back());

		luaL_checktype(L,-1,LUA_TTABLE);
		lua_Integer plen = luaL_len(L,-1);
		path.reserve(plen);
		for (lua_Integer i=1;i<=plen;++i) {
			lua_geti(L,-1,i);
			luaL_checktype(L,-1,LUA_TTABLE);
			lua_geti(L,-1,1);
			lua_geti(L,-2,2);
			lua_Number x = lua_tonumber(L,-2);
			lua_Number y = lua_tonumber(L,-1);
			geom::V v = self->m_t.transform(x,y);
			lua_pop(L,3);
			clipperlib::Point64 pnt(v.x*self->m_x_scale*1024,v.y*self->m_y_scale*1024);
			path.push_back(pnt);
		}
		
		self->m_clipper.AddPath(path,clipperlib::ptSubject,false);
		lua_pop(L,1);
	}
	return 0;
}

void Rasterizator::set_scale(double xs,double ys) {
	m_x_scale = xs;
	m_y_scale = ys;
}

void Rasterizator::do_start() {
	m_bounds = clipperlib::Rect64(INT64_MAX, INT64_MAX, INT64_MIN, INT64_MIN);
	for (clipperlib::Paths::const_iterator i=m_paths.begin();i!=m_paths.end();++i) {
		for (clipperlib::Path::const_iterator j=i->begin();j!=i->end();++j) {
			if (j->x < m_bounds.left) m_bounds.left = j->x;
			if (j->x > m_bounds.right) m_bounds.right = j->x;
			if (j->y < m_bounds.top) m_bounds.top = j->y;
			if (j->y > m_bounds.bottom) m_bounds.bottom = j->y;
		}
	}
	m_y_pos = m_bounds.top + 512;
	m_width = (m_bounds.right - m_bounds.left) / 1024;
	m_line.resize((m_width+7)/8);
	m_width = m_line.size() * 8;
	m_crnt_steps = 0;
}

static bool path_sort_pred(const clipperlib::Path& p1,const clipperlib::Path& p2) {
	if (p1.front().y == p2.front().y) {
		return p1.front().x < p2.front().x;
	}
	return p1.front().y < p2.front().y;
}
bool get_pix(clipperlib::Paths& paths,int64_t x,int64_t y) {
	while (!paths.empty()) {
		const clipperlib::Path& p(paths.front());
		if (p.front().y < y) {
			paths.erase(paths.begin());
			continue;
		}
		if (p.front().y > y) {
			return false;
		}
		if (p.back().x < x) {
			paths.erase(paths.begin());
			continue;
		}
		if (x > p.front().x) {
			return true;
		} else {
			return false;
		}
	}
	return false;
}
void Rasterizator::do_process() {
	if (m_crnt_steps == 0) {
		m_solutions.clear();
		clipperlib::Paths paths;
		int64_t y = m_y_pos;
		for (size_t i=0;i<m_num_steps;++i) {
			clipperlib::Path path;
			path.push_back(clipperlib::Point64(m_bounds.left,y));
			path.push_back(clipperlib::Point64(m_bounds.right,y));
			y += 1024;
			paths.push_back(path);
		}
		m_clipper.Clear();
		m_clipper.AddPaths(paths,clipperlib::ptSubject,true);
		m_clipper.AddPaths(m_paths,clipperlib::ptClip);
		clipperlib::Paths closed;
		
		m_clipper.Execute(clipperlib::ctIntersection, closed, m_solutions, clipperlib::frNonZero);
		std::sort(m_solutions.begin(),m_solutions.end(),path_sort_pred);
		m_crnt_steps = m_num_steps;
	}
	
	memset(m_line.data(),0,m_line.size());
	size_t len = m_line.size() * 8;
	for (size_t i=0;i<len;++i) {
		uint8_t& b(m_line[i/8]);
		uint8_t bit = 7-(i%8);
		if (get_pix(m_solutions,m_bounds.left+512+i*1024,m_y_pos)) {
			b |= (1 << bit);
		}
	}
	m_y_pos += 1024;
	--m_crnt_steps;
}

void Rasterizator::push_line(lua_State* L) {
	lua_pushlstring(L,reinterpret_cast<const char*>(m_line.data()),m_line.size());
}

void Rasterizator::start(lua_State* L) {
	if (!lua_isyieldable(L)) {
		luaL_error(L,"Rasterizator::start must call on thread");
	}
	{
		RasterizatorStartWorkRef req(new RasterizatorStartWork(RasterizatorRef(this)));
		lua_pushthread(L);
		int res = req->start(L);
		lua_llae_handle_error(L,"Rasterizator::start",res);
	}
	lua_yield(L,0);
}

void Rasterizator::process(lua_State* L) {
	if (!lua_isyieldable(L)) {
		luaL_error(L,"Rasterizator::process must call on thread");
	}
	{
		RasterizatorProcessWorkRef req(new RasterizatorProcessWork(RasterizatorRef(this)));
		lua_pushthread(L);
		int res = req->start(L);
		lua_llae_handle_error(L,"Rasterizator::process",res);
	}
	lua_yield(L,0);
}

RasterizatorWork::RasterizatorWork(const RasterizatorRef& rast) : m_rast(rast) {

}
RasterizatorWork::~RasterizatorWork() {

}

RasterizatorStartWork::RasterizatorStartWork(const RasterizatorRef& rast) : RasterizatorWork(rast) {

}

void RasterizatorStartWork::on_work() {
	printf("RasterizatorStartWork::on_work >>> \n");
	m_rast->do_start();
	printf("RasterizatorStartWork::on_work <<< \n");
}

RasterizatorProcessWork::RasterizatorProcessWork(const RasterizatorRef& rast) : RasterizatorWork(rast) {

}

int Rasterizator::get_line(lua_State* L) {
	RasterizatorRef self = RasterizatorRef::get_ref(L,1);
	self->push_line(L);
	return 1;
}

static uint8_t swap_bits(uint8_t v) {
	uint8_t r = 0;
	uint8_t l = 1;
	while (l) {
		r <<= 1;
		if (v&l) r|=1;
		l <<= 1;
	}
	return r;
}
void Rasterizator::inverse(lua_State*L) {
	size_t len = m_line.size() / 2;
	for (size_t i=0;i<len;++i) {
		uint8_t r = m_line[m_line.size()-i-1];
		uint8_t l = m_line[i];
		m_line[m_line.size()-i-1] = swap_bits(l);
		m_line[i] = swap_bits(r);
	}
	if (m_line.size() > len*2) {
		m_line[len] = swap_bits(m_line[len]);
	}
}
int Rasterizator::setup_transform(lua_State* L) {
	RasterizatorRef self = RasterizatorRef::get_ref(L,1);

	luaL_checktype(L,2,LUA_TTABLE);
	luaL_checktype(L,3,LUA_TTABLE);
	geom::V p1;
	lua_getfield(L,2,"x");
	p1.x = lua_tonumber(L,-1);
	lua_pop(L,1);
	lua_getfield(L,2,"y");
	p1.y = lua_tonumber(L,-1);
	lua_pop(L,1);
	geom::V pp1;
	lua_getfield(L,2,"px");
	pp1.x = lua_tonumber(L,-1);
	lua_pop(L,1);
	lua_getfield(L,2,"py");
	pp1.y = lua_tonumber(L,-1);
	lua_pop(L,1);
	geom::V p2;
	lua_getfield(L,3,"x");
	p2.x = lua_tonumber(L,-1);
	lua_pop(L,1);
	lua_getfield(L,3,"y");
	p2.y = lua_tonumber(L,-1);
	lua_pop(L,1);
	geom::V pp2;
	lua_getfield(L,3,"px");
	pp2.x = lua_tonumber(L,-1);
	lua_pop(L,1);
	lua_getfield(L,3,"py");
	pp2.y = lua_tonumber(L,-1);
	lua_pop(L,1);

	std::cout << "p1:" << p1.x << ", " << p1.y << std::endl;
	std::cout << "p2:" << p2.x << ", " << p2.y << std::endl;
	
	std::cout << "pp1:" << pp1.x << ", " << pp1.y << std::endl;
	std::cout << "pp2:" << pp2.x << ", " << pp2.y << std::endl;
	
	geom::V vo = p2 - p1;
	geom::V vt = pp2 - pp1; // pp2 + (pp1-p1) - pp1 = pp2-p1-pp1
	double diro = vo.norm().dir();
	double dirt = vt.norm().dir();

	std::cout << "doro: " << diro << ", dirt: " << dirt << std::endl;

	geom::T t;
	t.translate(p1).rotate(dirt-diro).translate(-p1);

	std::cout << "v: " << t.v.x << "," << t.v.y << std::endl;
	std::cout << "m: " << t.m.m[0] << "," << t.m.m[1] << "," << t.m.m[2] << "," << t.m.m[3] << std::endl;
	self->m_t = t;
	return 0;
}

void RasterizatorProcessWork::on_work() {
	m_rast->do_process();
}

int Rasterizator::lbind(lua_State* L) {
	luaL_newmetatable(L,Rasterizator_mt);
	lua_newtable(L);
	luabind::bind(L,"new",&Rasterizator::lnew);
	luabind::bind(L,"set_scale",&Rasterizator::set_scale);
	luabind::bind(L,"add_paths",&Rasterizator::add_paths);
	luabind::bind(L,"start",&Rasterizator::start);
	luabind::bind(L,"process",&Rasterizator::process);
	luabind::bind(L,"complete",&Rasterizator::complete);
	luabind::bind(L,"get_y_pos",&Rasterizator::get_y_pos);
	luabind::bind(L,"get_y_start",&Rasterizator::get_y_start);
	luabind::bind(L,"get_y_len",&Rasterizator::get_y_len);
	luabind::bind(L,"get_line",&Rasterizator::get_line);
	luabind::bind(L,"get_width",&Rasterizator::get_width);
	luabind::bind(L,"get_height",&Rasterizator::get_height);
	luabind::bind(L,"get_left",&Rasterizator::get_left);
	luabind::bind(L,"inverse",&Rasterizator::inverse);
	luabind::bind(L,"setup_transform",&Rasterizator::setup_transform);
	lua_setfield(L,-2,"__index");
	lua_pushcfunction(L,&RasterizatorRef::gc);
	lua_setfield(L,-2,"__gc");
	lua_pop(L,1);
	return 0;
}

