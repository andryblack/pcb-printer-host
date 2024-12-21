local class = require 'llae.class'
local log = require 'llae.log'
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

function Geometry.new_circle( x, y, r , vertices, rot, rev)
	local p = {}
	local points = vertices or 32
	local ir = rot and (rot * math.pi / 180) or 0
	for i = 1,points do
		local a = ((math.pi * 2 * (i-1)) / points + ir) * (rev and -1.0 or 1.0)
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

function Geometry.new_line( sx, sy, ex, ey, w)
	local p = {}
	
	local dx = ex - sx
	local dy = ey - sy

	local len = math.sqrt(dx*dx + dy*dy)
	local x,y
	if len == 0 then
		x = 0
		y = w
	else
		x = (dx / len)*w*0.5
		y = (dy / len)*w*0.5
		x,y = -y,x -- rotate CCW 90
	end


	table.insert(p,add_point({sx,sy},-x,-y))--transform_point(-w/2,-h/2,s,c),x,y))
	table.insert(p,add_point({ex,ey},-x,-y))--transform_point( w/2,-h/2,s,c),x,y))
	table.insert(p,add_point({ex,ey}, x, y))--extransform_point( w/2, h/2,s,c),x,y))
	table.insert(p,add_point({sx,sy}, x, y))--transform_point(-w/2, h/2,s,c),x,y))

	return Geometry.new({clipperlib.Path.import(p)})
end


function Geometry.new_path_buffer( path , width )
	local c = clipperlib.ClipperOffset.new()
	c:add_path(clipperlib.Path.import(path),clipperlib.JoinType.Round,clipperlib.EndType.OpenRound)
	local r,err = c:execute(width/2)
	if not r then
		error('failed execute: ' .. tostring(err))
	end
	return Geometry.new(r)
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
		local closed,open = self._c:execute(self._op,fill_rule)
		if closed then
			self:clear()
			self._g = closed
		else
			error('failed execute: ' .. tostring(open))
		end
		self._c:clear()
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

function Geometry:difference( g , move)
	--self:flush()
	if not next(self._g) then
		self:flush()
	end
	if not next(self._g) then
		log.error('difference: empty source')
		if move then
			g:clear()
		end
		return
	end
	g:flush()
	self:begin_op(clipperlib.ClipType.Difference)
	self._c:add_paths(g._g,clipperlib.PathType.Clip)
	if move then
		g:clear()
	end
end

function Geometry:union( g , move)
	g:flush()
	if not self._g then
		self:flush()
	end
	if not next(self._g) then
		self._g = g._g
	else
		self:begin_op( clipperlib.ClipType.Union )
		self._c:add_paths(g._g,clipperlib.PathType.Clip)
		if move then
			g:clear()
		end
	end
end

function Geometry:dump( n )
	self:flush()
	local l = {}
	for _,v in ipairs(self._g) do
		-- local c = {}
		-- for _,j in ipairs(v) do
		-- 	table.insert(c,string.format('{%d,%d}',j[1],j[2]))
		-- end
		-- table.insert(l,'{'..table.concat(c,',')..'}')
		table.insert(l,'[' .. tostring(v) .. ']')
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
