#ifndef _RASTERIZATOR_H_INCLUDED_
#define _RASTERIZATOR_H_INCLUDED_

#include <meta/object.h>
#include <lua/state.h>
#include <common/intrusive_ptr.h>
#include "clipperlib/clipper.h"
#include <cmath>

namespace geom {

	struct V {
		double x;
		double y;
		V() : x(0.0),y(0.0) {}
		V(double x,double y):x(x),y(y) {}
		V(const V& v) : x(v.x),y(v.y) {}
		V operator + (const V& v) const {
			return V(x+v.x,y+v.y);
		}
		V operator - (const V& v) const {
			return V(x-v.x,y-v.y);
		}
		V& operator += (const V& v) {
			x += v.x;
			y += v.y;
			return *this;
		}
		V& operator -= (const V& v) {
			x -= v.x;
			y -= v.y;
			return *this;
		}
		V operator - () const {return V(-x , -y);}
		double dir() const {
        	return atan2(x, -y);
        }
        double len() const {
        	return sqrt(x*x+y*y);
        }
        V norm() const {
        	double l = len();
        	return V(x/l,y/l);
        }
	};

	struct M {
		double m[4];
		M(double m00,double m01,double m10,double m11) {
			m[0 * 2 + 0] = m00; m[0 * 2 + 1] = m01;
            m[1 * 2 + 0] = m10; m[1 * 2 + 1] = m11;
		}
		static M identity() { return M(1.0,0.0,0.0,1.0);}
		M operator *(const M &o) const { 
            return M( 
                m[0*2+0]*o.m[0*2+0]+m[1*2+0]*o.m[0*2+1],
                m[0*2+1]*o.m[0*2+0]+m[1*2+1]*o.m[0*2+1],
                m[0*2+0]*o.m[1*2+0]+m[1*2+0]*o.m[1*2+1],
                m[0*2+1]*o.m[1*2+0]+m[1*2+1]*o.m[1*2+1]
            );
        }
        M& operator *=(const M &o)  { 
            return *this = *this * o;
        }
	};

	inline V operator * (const V& v, const M& m)
    {
            return V(
                    m.m[0*2+0]*v.x + m.m[0*2+1]*v.y,
                    m.m[1*2+0]*v.x + m.m[1*2+1]*v.y);
    }

    inline V operator * (const M& m, const V& v)
    {
            return V(
                    m.m[0*2+0]*v.x + m.m[1*2+0]*v.y,
                    m.m[0*2+1]*v.x + m.m[1*2+1]*v.y);
    }

	struct T {
		M m;
		V v;
		T() : m(M::identity()) {}
		T& rotate(double a) {
			double c = ::cos(a);
            double s = ::sin(a);
            m*=M(c,s,-s,c);
            return *this;
		}
		T& rotate(const V& dir) {
			double c = dir.x;
            double s = -dir.y;
            m*=M(c,s,-s,c);
            return *this;
		}
		T& translate(const V& t) {
			v+=m*t;
            return *this;
		}
		T& scale(const V& s) {
			m*=M(s.x,0,0,s.y);
            return *this;
		}

		V transform(double x,double y) const {
            return V(    v.x+m.m[0*2+0]*x + m.m[1*2+0]*y,
                                v.y+m.m[0*2+1]*x + m.m[1*2+1]*y);
        }
	};

}

class Rasterizator;
typedef common::intrusive_ptr<Rasterizator> RasterizatorPtr;


class Rasterizator : public meta::object {
	META_OBJECT
private:
	clipperlib::Clipper m_clipper;
	double m_x_scale;
	double m_y_scale;

	geom::T 	m_t;

	clipperlib::Rect64 m_bounds;
	int64_t m_y_pos;
	std::vector<uint8_t> m_line;
	size_t m_width;
	clipperlib::Paths m_paths;
	size_t m_num_steps;
	size_t m_crnt_steps;
	clipperlib::Paths m_solutions;

	void do_start();
	void do_process();

	class RasterizatorWork;
	class RasterizatorStartWork;
	class RasterizatorProcessWork;
public:
	Rasterizator();
	void set_scale(double xs,double ys);

	static lua::multiret lnew(lua::state& l);
	static void lbind(lua::state& l);

	void add_paths(lua::state& l);
	lua::multiret get_line(lua::state& l);

	void setup_transform(lua::state& L);

	
	bool complete() const { return m_y_pos > m_bounds.bottom; }
	double get_y_pos() const { return m_y_pos / (m_y_scale * 1024); }
	double get_y_start() const { return m_bounds.top / (m_y_scale * 1024); }
	double get_y_len() const { return (m_bounds.bottom-m_bounds.top) / (m_y_scale * 1024); }
	void push_line(lua::state& l);
	int64_t get_width() const { return m_width; }
	int64_t get_height() const { return (m_bounds.bottom-m_bounds.top) / 1024; }
	int64_t get_left() const { return m_bounds.left / 1024; }
	int64_t get_top() const { return m_bounds.top / 1024;}
	void inverse(lua::state& l);
	lua::multiret start(lua::state& l);
	lua::multiret process(lua::state& l);
};


#endif /*_RASTERIZATOR_H_INCLUDED_*/