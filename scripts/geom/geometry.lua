local class = require 'llae.class'
local clipperlib = require 'clipperlib'

local Geometry = class(nil,'Geometry')

local fill_rule = clipperlib.FillRule.NonZero

function Geometry:_init( points )
	self._g = points
end

function Geometry.import( polygons , scale)
	local r = {}
	for _,v in ipairs(polygons) do
		table.insert(r,clipperlib.Path.import(v,scale))
	end
	return Geometry.new(r)
end

function Geometry.new_polygon( points )
	return Geometry.new({clipperlib.Path.import(points)})
end

function Geometry.new_circle( x, y, r , vertices, rot)
	local p = {}
	local points = vertices or 32
	local ir = rot and (rot * math.pi / 180) or 0
	for i = 1,points do
		local a = (math.pi * 2 * (i-1)) / points + ir
		local s,c = math.sin(a) * r,math.cos(a) * r
		table.insert(p,{math.floor(x+s),math.floor(y-c)})
	end
	return Geometry.new({clipperlib.Path.import(p)})
end

local function transform_point( x, y, s, c )
	return { x * c - y * s, y * c + x * s }
end
local function add_point( p , x, y)
	p[1] = math.floor(x + p[1])
	p[2] = math.floor(y + p[2])
	return p 
end 
function Geometry.new_rect( x, y, w, h, rot)
	local p = {}
	local a = rot and (rot * math.pi / 180) or 0
	local s,c = math.sin(a),math.cos(a)

	table.insert(p,add_point(transform_point(-w/2,-h/2,s,c),x,y))
	table.insert(p,add_point(transform_point( w/2,-h/2,s,c),x,y))
	table.insert(p,add_point(transform_point( w/2, h/2,s,c),x,y))
	table.insert(p,add_point(transform_point(-w/2, h/2,s,c),x,y))

	return Geometry.new({clipperlib.Path.import(p)})
end


function Geometry.new_path_buffer( path , width )
	local c = clipperlib.ClipperOffset.new()
	c:add_path(clipperlib.Path.import(path),clipperlib.JoinType.Round,clipperlib.EndType.OpenRound)
	return Geometry.new(c:execute(width/2))
end

function Geometry:clear( )
	if self._g then
		for _,v in ipairs(self._g) do
			v:clear()
		end
		self._g = {}
	end
end
function Geometry:flush( )
	if self._c then
		local r,closed,open = self._c:execute(self._op,fill_rule)
		if r then
			self:clear()
			self._g = closed
		else
			error('failed execute')
		end
		self._c = nil
		self._op = nil
	end
end

function Geometry:begin_op( op )
	if self._op and op == self._op then
		return
	end
	self:flush()
	self._op = op
	self._c = clipperlib.Clipper.new()
	self._c:add_paths(self._g,clipperlib.PathType.Subject)
end

function Geometry:difference( g )
	if not next(self._g) then
		error('difference: empty source')
	end
	g:flush()
	self:begin_op(clipperlib.ClipType.Difference)
	self._c:add_paths(g._g,clipperlib.PathType.Clip)
end

function Geometry:union( g )
	g:flush()
	if not self._g then
		self:flush()
	end
	if not next(self._g) then
		self._g = g._g
	else
		self:begin_op( clipperlib.ClipType.Union )
		self._c:add_paths(g._g,clipperlib.PathType.Clip)
	end
end

function Geometry:dump( n )
	self:flush()
	local l = {}
	for _,v in ipairs(self._g) do
		local c = {}
		for _,j in ipairs(v) do
			table.insert(c,string.format('{%d,%d}',j[1],j[2]))
		end
		table.insert(l,'{'..table.concat(c,',')..'}')
	end
	return '[' .. table.concat(l,',') .. ']'
end

function Geometry:buffer( width )
	self:flush()
	local c = clipperlib.ClipperOffset.new()
	c:add_paths(self._g,clipperlib.JoinType.Miter,clipperlib.EndType.Polygon)
	self:clear()
	self._g = c:execute(width/2)
end

function Geometry:export( scale )
	self:flush()
	local r = {}
	for _,g in ipairs(self._g) do
		table.insert(r,g:export(scale))
	end
	return r
end

function Geometry:translate( x, y )
	local d = self:export(1.0)
	for _,pgn in ipairs(d) do
		for __,p in ipairs(pgn) do
			p[1] = p[1] + x
			p[2] = p[2] + y
		end
	end
	return Geometry.import(d,1.0)
end


return Geometry
