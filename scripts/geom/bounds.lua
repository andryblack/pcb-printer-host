local class = require 'llae.class'

local Bounds = class(nil,'geom.Bounds')

function Bounds:_init( x,y,w,h )
	if x then
		self._min_x = x
		self._min_y = y
		if w then
			self._max_x = x + w
			self._max_y = y + h
		end
	end
end

function Bounds:copy(  )
	local r = Bounds.new()
	r._min_x = self._min_x
	r._min_y = self._min_y
	r._max_x = self._max_x
	r._max_y = self._max_y
	return r
end

function Bounds:flip_x(  )
	self._min_x,self._max_x = -self._max_x,-self._min_x
end

function Bounds:flip_y( )
	self._min_y,self._max_y = -self._max_y,-self._min_y
end

function Bounds:extend( x, y )
	if not self._min_x or x < self._min_x then
		self._min_x = x
	end
	if not self._max_x or x > self._max_x then
		self._max_x = x
	end
	if not self._min_y or y < self._min_y then
		self._min_y = y
	end
	if not self._max_y or y > self._max_y then
		self._max_y = y
	end
end

function Bounds:is_empty(  )
	return not self._min_x or not self._min_y
end

function Bounds:intersect( bounds )
	self:extend(bounds._min_x,bounds._min_y)
	self:extend(bounds._max_x,bounds._max_y)
end

function Bounds:x(  )
	return self._min_x or 0
end

function Bounds:y(  )
	return self._min_y or 0
end

function Bounds:width(  )
	return (self._max_x or 0) - (self._min_x or 0)
end

function Bounds:height(  )
	return (self._max_y or 0) - (self._min_y or 0)
end

function Bounds:scale( s )
	self._min_x = (self._min_x or 0) * s
	self._min_y = (self._min_y or 0) * s
	self._max_x = (self._max_x or 0) * s
	self._max_y = (self._max_y or 0) * s
end

function Bounds:extend_points( points )
	for _,v in ipairs(points) do
		self:extend( v[1], v[2] )
	end
end

return Bounds
