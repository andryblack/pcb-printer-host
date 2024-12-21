#include "rasterizator.h"
#include "rasterizator_write.h"
#include <uv/luv.h>
#include <uv/work.h>
#include <lua/bind.h>
#include <algorithm>
#include <iostream>

META_OBJECT_INFO(Rasterizator,meta::object)

Rasterizator::Rasterizator() : m_x_scale(1.0),m_y_scale(1.0),m_bounds(INT64_MAX, INT64_MAX, INT64_MIN, INT64_MIN) {
	m_num_steps = 32;
}

lua::multiret Rasterizator::lnew(lua::state& l) {
	lua::push(l,RasterizatorPtr(new Rasterizator()));
	return {1};
}
void Rasterizator::add_paths(lua::state& l) {
	l.checktype(2,lua::value_type::table);
	lua_Integer len = l.len(2);
	m_paths.reserve(m_paths.size()+len);
	for (lua_Integer p=1;p<=len;++p) {
		l.geti(2,p);
		
		m_paths.push_back(clipperlib::Path());
		clipperlib::Path& path(m_paths.back());

		l.checktype(-1,lua::value_type::table);
		lua_Integer plen = l.len(-1);
		path.reserve(plen);
		for (lua_Integer i=1;i<=plen;++i) {
			l.geti(-1,i);
			l.checktype(-1,lua::value_type::table);
			l.geti(-1,1);
			l.geti(-2,2);
			lua_Number x = l.tonumber(-2);
			lua_Number y = l.tonumber(-1);
			geom::V v = m_t.transform(x,y);
			l.pop(3);
			clipperlib::Point64 pnt(v.x*m_x_scale*1024,v.y*m_y_scale*1024);
			path.push_back(pnt);
		}
		
		m_clipper.AddPath(path,clipperlib::ptSubject,false);
		l.pop(1);
	}
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

void Rasterizator::push_line(lua::state& l) {
	l.pushlstring(reinterpret_cast<const char*>(m_line.data()),m_line.size());
}

class Rasterizator::RasterizatorWork : public uv::lua_cont_work {
public:
protected:
	RasterizatorPtr m_rast;
	RasterizatorWork( RasterizatorPtr&& rast) : m_rast(std::move(rast)) {

	}
	virtual int resume_args(lua::state& l,int status) {
		if (status != 0) {
			l.pushnil();
            uv::push_error(l,status);
            return 2;
		}
		l.pushboolean(true);
		return 1;
	}
};

class Rasterizator::RasterizatorStartWork : public Rasterizator::RasterizatorWork {
protected:
	virtual void on_work() override {
		m_rast->do_start();
	}
public:
	RasterizatorStartWork( RasterizatorPtr&& rast ) : RasterizatorWork(std::move(rast)) {

	}
};

class Rasterizator::RasterizatorProcessWork : public Rasterizator::RasterizatorWork {
protected:
	virtual void on_work() override {
		m_rast->do_process();
	}
public:
	RasterizatorProcessWork( RasterizatorPtr&& rast ) : RasterizatorWork(std::move(rast)) {

	}
};

lua::multiret Rasterizator::start(lua::state& l) {
	if (!l.isyieldable()) {
		l.error("Rasterizator::start async");
	}
	{

		common::intrusive_ptr<RasterizatorStartWork> req{new RasterizatorStartWork(RasterizatorPtr(this))};

		int r = req->queue_work_thread(l);
		if (r < 0) {
			req->reset(l);
			l.pushnil();
			uv::push_error(l,r);
			return {2};
		} 
	}
	l.yield(0);
	return {1};
}

lua::multiret Rasterizator::process(lua::state& l) {
	if (!l.isyieldable()) {
		l.error("Rasterizator::start async");
	}
	{

		common::intrusive_ptr<RasterizatorProcessWork> req{new RasterizatorProcessWork(RasterizatorPtr(this))};

		int r = req->queue_work_thread(l);
		if (r < 0) {
			req->reset(l);
			l.pushnil();
			uv::push_error(l,r);
			return {2};
		} 
	}
	l.yield(0);
	return {1};
}

lua::multiret Rasterizator::get_line(lua::state& l) {
	push_line(l);
	return {1};
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
void Rasterizator::inverse(lua::state& l) {
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
void Rasterizator::setup_transform(lua::state& l) {
	l.checktype(2,lua::value_type::table);
	l.checktype(3,lua::value_type::table);
	geom::V p1;
	l.getfield(2,"x");
	p1.x = l.tonumber(-1);
	l.pop(1);
	l.getfield(2,"y");
	p1.y = l.tonumber(-1);
	l.pop(1);
	geom::V pp1;
	l.getfield(2,"px");
	pp1.x = l.tonumber(-1);
	l.pop(1);
	l.getfield(2,"py");
	pp1.y = l.tonumber(-1);
	l.pop(1);
	geom::V p2;
	l.getfield(3,"x");
	p2.x = l.tonumber(-1);
	l.pop(1);
	l.getfield(3,"y");
	p2.y = l.tonumber(-1);
	l.pop(1);
	geom::V pp2;
	l.getfield(3,"px");
	pp2.x = l.tonumber(-1);
	l.pop(1);
	l.getfield(3,"py");
	pp2.y = l.tonumber(-1);
	l.pop(1);

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
	m_t = t;
	
}

void Rasterizator::lbind(lua::state& l) {
	lua::bind::function(l,"new",&Rasterizator::lnew);
	lua::bind::function(l,"set_scale",&Rasterizator::set_scale);
	lua::bind::function(l,"add_paths",&Rasterizator::add_paths);
	lua::bind::function(l,"start",&Rasterizator::start);
	lua::bind::function(l,"process",&Rasterizator::process);
	lua::bind::function(l,"complete",&Rasterizator::complete);
	lua::bind::function(l,"get_y_pos",&Rasterizator::get_y_pos);
	lua::bind::function(l,"get_y_start",&Rasterizator::get_y_start);
	lua::bind::function(l,"get_y_len",&Rasterizator::get_y_len);
	lua::bind::function(l,"get_line",&Rasterizator::get_line);
	lua::bind::function(l,"get_width",&Rasterizator::get_width);
	lua::bind::function(l,"get_height",&Rasterizator::get_height);
	lua::bind::function(l,"get_left",&Rasterizator::get_left);
	lua::bind::function(l,"inverse",&Rasterizator::inverse);
	lua::bind::function(l,"setup_transform",&Rasterizator::setup_transform);
}

int luaopen_rasterizator(lua_State* L) {
	lua::state l(L);
	lua::bind::object<Rasterizator>::register_metatable(l,&Rasterizator::lbind);
	lua::bind::object<RasterizatorWrite>::register_metatable(l,&RasterizatorWrite::lbind);
	l.createtable();
	

	lua::bind::object<Rasterizator>::get_metatable(l);
	l.setfield(-2,"Rasterizator");
	lua::bind::object<RasterizatorWrite>::get_metatable(l);
	l.setfield(-2,"RasterizatorWrite");
	return 1;
}