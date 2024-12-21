local class = require 'llae.class'
local log = require 'llae.log'

local Contour = require 'geom.contour'

local Region = class(nil,'gerber.Region')

function Region:_init( parent , current_pos , polarity )
	self._parent = parent
	self._geometry = nil
	self._current_pos = { current_pos[1], current_pos[2]}
	self._polarity = polarity
end

function Region:flush_contour(  )
	if self._contour and self._contour:num_points()>1 then
		if not self._contour:is_closed() then
			self._contour:close()
			if not self._contour:is_closed() then
				self._contour:dump()
				error('invalid contour')
			end
		end
		--log.info('Region:flush_contour')
		--self._contour:dump()
		local g = self._contour:build_polygon()
		if self._geometry then
			self._geometry:union(g,true)
		else
			self._geometry = g
		end
	end
	self._contour = nil
end

function Region:finish(  )
	self:flush_contour()
	if not self._geometry then
		error('empty region')
	end
	self._geometry:flush()
	return self._geometry
end

function Region:move( x , y )
	self:flush_contour()
	self._current_pos = { x or self._current_pos[1],y or self._current_pos[2] }
	self._contour = Contour.new()
	--log.info('Region:move',self._current_pos[1],self._current_pos[2])
	self._contour:add_segment(self._current_pos[1],self._current_pos[2])
end

function Region:draw( x, y , interpolation )
	self._current_pos = { x or self._current_pos[1],y or self._current_pos[2] }
	--log.info('Region:draw',self._current_pos[1],self._current_pos[2])
	self._contour:add_segment(self._current_pos[1],self._current_pos[2], interpolation)
end

function Region:get_last_pos(  )
	return self._current_pos
end

return Region