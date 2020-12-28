local class = require 'llae.class'

local Geometry = require 'geom.geometry'

local Aperture = class(nil,'gerber.Aperture')

local function parse_params( data )
	local r = {}
	for p in string.gmatch(data, '([%.%d]+)X?') do
		table.insert(r,tonumber(p))
	end
	return r
end 

function Aperture:_init(  )

end

function Aperture:draw_contour( canvas, contour )
	error('pure virtual aperture call')
end
function Aperture:flash( canvas, contour )
	error('pure virtual aperture call')
end


local ApertureCircle = class(Aperture,'gerber.ApertureCircle')

function ApertureCircle:_init( diameter, hole )
	self._diameter = diameter
	self._hole = hole
end

function ApertureCircle:draw_contour( canvas, contour )
	local g = contour:build_buffer(self._diameter)
	canvas:union(g,true)
	return canvas
end
function ApertureCircle:flash( canvas, x, y )
	--print('circle flash: ',x,y,self._diameter)
	local g = Geometry.new_circle(x,y,self._diameter / 2)
	--print(g:dump())
	canvas:union(g,true)
	return canvas
end


function Aperture.new_std_C( data , s)
	local p = parse_params(data)
	if not p[1] then
		error('C need diameter')
	end
	return ApertureCircle.new(p[1]*s,p[2] and p[2]*s)
end

local AperturePolygon = class(Aperture,'gerber.AperturePolygon')

function AperturePolygon:_init( diameter, vertices, rot, hole )
	self._diameter = diameter
	self._vertices = vertices
	self._rot = rot
	self._hole = hole
end
function AperturePolygon:draw_contour( canvas, contour )
	error('draw polygon not supported')
	return canvas
end

function AperturePolygon:flash( canvas, x , y )
	--print('circle flash: ',x,y,self._diameter)
	local g = Geometry.new_circle(x,y,self._diameter / 2,self._vertices,self._rot)
	--print(g:dump())
	canvas:union(g,true)
	return canvas
end

function Aperture.new_std_P( data , s)
	local p = parse_params(data)
	if not p[1] then
		error('P need Outer diameter')
	end
	if not p[2] then
		error('P need Number of vertices')
	end
	return AperturePolygon.new(p[1]*s,p[2],p[3],p[4] and p[4]*s)
end

local ApertureRectangle = class(Aperture,'gerber.ApertureRectangle')

function ApertureRectangle:_init( w,h , hole )
	self._w = w
	self._h = h
	self._hole = hole
end

function ApertureRectangle:draw_contour( canvas, contour )
	error('draw rectangle not supported')
	return canvas
end

function ApertureRectangle:flash( canvas, x, y )
	local w = self._w
	local h = self._h
	local g = Geometry.new_polygon{
		{x-w/2,y-h/2},
		{x+w/2,y-h/2},
		{x+w/2,y+h/2},
		{x-w/2,y+h/2},
		
	}
	canvas:union(g,true)
	return canvas
end


function Aperture.new_std_R( data , s)
	local p = parse_params(data)
	if not p[1] then
		error('P need X size')
	end
	if not p[2] then
		error('P need Y size')
	end
	return ApertureRectangle.new(p[1]*s,p[2]*s,p[3] and p[3]*s)
end


local ApertureObround = class(Aperture,'gerber.ApertureObround')

function ApertureObround:_init( x, y, hole )
	self._x = x
	self._y = y
	self._hole = hole
end

function ApertureObround:draw_contour( canvas, contour )
	error('only flash supported for Obround')
	return canvas
end
function ApertureObround:flash( canvas, x, y )
	--print('circle flash: ',x,y,self._diameter)
	if self._x < self._y then
		local g1 = Geometry.new_circle(x,y+self._y/2-self._x/2,self._x / 2)
		local g2 = Geometry.new_circle(x,y-self._y/2+self._x/2,self._x / 2)
		g2:union(g1,true)
		--print(g:dump())
		canvas:union(g2,true)
	else
		local g1 = Geometry.new_circle(x+self._x/2-self._y/2,y,self._y / 2)
		local g2 = Geometry.new_circle(x-self._x/2+self._y/2,y,self._y / 2)
		g2:union(g1,true)
		--print(g:dump())
		canvas:union(g2,true)
	end
	return canvas
end

function Aperture.new_std_O( data , s)
	local p = parse_params(data)
	if not p[1] then
		error('O need X size')
	end
	if not p[2] then
		error('O need Y size')
	end
	return ApertureObround.new(p[1]*s,p[2]*s,p[3] and p[3]*s)
end

local ApertureMacros = class(Aperture,'gerber.ApertureMacros')

ApertureMacros._primitives = {}

ApertureMacros._primitives[1] = function(self,data) 
	local exp,dia,x,y = string.match(data,'^([01]),([%d.]+),([%d.-]+),([%d.-]+)')
	if not exp then
		error('invalid circle data ' .. data)
	end
	x = tonumber(x)
	y = tonumber(y)
	dia = tonumber(dia)
	--print('circle',x,y,dia)
	if not self._canvas then
		self._canvas = Geometry.new_circle(x*self._s,y*self._s,dia*self._s / 2, num, angle)
	else
		self._canvas:union( Geometry.new_circle(x*self._s,y*self._s,dia*self._s / 2, num, angle ), true )
	end
end

ApertureMacros._primitives[5] = function(self,data) 
	local exp,num,x,y,dia,angle = string.match(data,'^([01]),([%d.]+),([%d.-]+),([%d.-]+),([%d.-xX$]+),([%d.-]+)')
	if not exp then
		error('invalid polygonn data ' .. data)
	end
	x = tonumber(x)
	y = tonumber(y)
	dia = self:parse_args(dia,'dia')
	num = tonumber( num )
	angle = tonumber( angle )
	--print('circle',x,y,dia)
	if not self._canvas then
		self._canvas = Geometry.new_circle(x*self._s,y*self._s,dia*self._s / 2)
	else
		self._canvas:union( Geometry.new_circle(x*self._s,y*self._s,dia*self._s / 2) , true )
	end
end

ApertureMacros._primitives[21] = function(self,data) 
	local exp,w,h,x,y,r = string.match(data,'^([01]),([%d.]+),([%d.]+),([%d.-]+),([%d.-]+),([%d.-]+)')
	if not exp then
		error('invalid Center Line data ' .. data)
	end
	w = tonumber(w)
	h = tonumber(h)
	x = tonumber(x)
	y = tonumber(y)
	r = tonumber(r)
	--print('rect',x,y,w,h,r)
	if not self._canvas then
		self._canvas = Geometry.new_rect(x*self._s,y*self._s,w*self._s,h*self._s,r)
	else
		self._canvas:union( Geometry.new_rect(x*self._s,y*self._s,w*self._s,h*self._s,r) )
	end
end

function ApertureMacros:flash( canvas, x, y )
	canvas:union(self._canvas:translate(x,y))
	return canvas
end

function ApertureMacros:parse_args( str, name )
	local const,arg = string.match(str,'([%d.-]+)[Xx](%$%d+)')
	if const then
		print('found variable')
		return tostring(const)
	end
	return tonumber(str)
end

function ApertureMacros:_init( s )
	self._s = s
end
function ApertureMacros:primitive( code, data )
	if not ApertureMacros._primitives[code] then
		error('unknown primitive code ' .. code)
	end
	ApertureMacros._primitives[code](self,data)
end
function Aperture.macros( blocks , s)
	local m = ApertureMacros.new(s)
	for i=2,#blocks do
		local block = blocks[i]
		local code,tail = string.match(block,'^(%d+),(.+)$')
		if code then
			m:primitive(tonumber(code),tail)
		end
	end
	return m
end

return Aperture
