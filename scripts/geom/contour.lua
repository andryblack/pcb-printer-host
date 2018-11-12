local class = require 'llae.class'
local Geometry = require 'geom.geometry'

local Contour = class(nil,'geom.Contour')


function Contour:_init(  )
	self._points = {}
end

function Contour:add_segment( x , y )
	table.insert(self._points,{x,y})
end

function Contour:num_points( )
	return #self._points
end

function Contour:close(  )
	assert(#self._points > 2, 'invalid points count')
	self:add_segment(self._points[1][1],self._points[1][2])
end

function Contour:is_closed(  )
	local len = #self._points
	return len > 2 and 
		(self._points[1][1] == self._points[len][1]) and
		(self._points[1][2] == self._points[len][2])
end


function Contour:points( )
	local len = #self._points
	local i = 0
	return function ( )
		i = i + 1
		return i < len and self._points[i] or nil
	end
end

function Contour:build_polygon(  )
	local g =  Geometry.new_polygon(self._points)
	return g
end

function Contour:build_buffer( w )
	local g =  Geometry.new_path_buffer(self._points , w)
	return g
end


function Contour:build_path(  )
	return Geometry.new_path(self._points)
end

return Contour