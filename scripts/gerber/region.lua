local class = require 'llae.class'

local Contour = require 'geom.contour'

local Region = class(nil,'gerber.Region')

function Region:_init( parent , current_pos , polarity )
	self._parent = parent
	self._geometry = nil
	self._current_pos = { current_pos[1], current_pos[2]}
	self._polarity = polarity
end

function Region:flush_contour(  )
	if self._contour then
		if not self._contour:is_closed() then
			self._contour:close()
			if not self._contour:is_closed() then
				self._contour:dump()
				error('invalid contour')
			end
		end
		local g = self._contour:build_polygon()
		if self._geometry then
			self._geometry:union(g)
		else
			self._geometry = g
		end

		self._contour = nil
	end
end

function Region:finish(  )
	self:flush_contour()
	if not self._geometry then
		error('empty region')
	end
end

function Region:move( x , y )
	self:flush_contour()
	self._current_pos = { x or self._current_pos[1],y or self._current_pos[2] }
	self._contour = Contour.new()
	--print('Region:move',self._current_pos[1],self._current_pos[2])
	self._contour:add_segment(self._current_pos[1],self._current_pos[2])
end

function Region:draw( x, y )
	self._current_pos = { x or self._current_pos[1],y or self._current_pos[2] }
	--print('Region:draw',self._current_pos[1],self._current_pos[2])
	self._contour:add_segment(self._current_pos[1],self._current_pos[2])
end

function Region:get_last_pos(  )
	return self._current_pos
end

return Region