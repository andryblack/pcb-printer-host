local class = require 'llae.class'
local log = require 'llae.log'
local Geometry = require 'geom.geometry'

local Contour = class(nil,'geom.Contour')


function Contour:_init(  )
	self._points = {}
end

function Contour:add_segment( x , y , interpolation)
	if interpolation then
		local len = #self._points
		if len == 0 then
			error( 'undefined start point' )
		end
		local start_point = self._points[len]
		
		local center = {
			start_point[1] + interpolation.i,
			start_point[2] + interpolation.j
		}
		local dir_start = math.atan( start_point[2]-center[2], start_point[1]-center[1] )
		local dir_end = math.atan( y-center[2], x-center[1] )
		--print('dir:',dir_start,dir_end)
		local num_points = 5
		local r = math.sqrt( (start_point[1]-center[1])*(start_point[1]-center[1])+
									(start_point[2]-center[2])*(start_point[2]-center[2]) )

		--print('r:',r)
		if interpolation.t == 'ccw' then
			if dir_end < dir_start then
				dir_end = dir_end + math.pi * 2
			end
			--print('dir:',dir_start,dir_end)
			local dir_len = dir_end - dir_start
			local dir_step = dir_len / (num_points + 1)
			--print('dir_len',dir_len,'dir_step',dir_step)
			local dir = dir_start + dir_step
			for i=1,num_points do

				local xx = center[1] + r*math.cos( dir )
				local yy = center[2] + r*math.sin( dir )
				print('add cw point',xx,yy)
				table.insert(self._points,{xx,yy})
				dir = dir + dir_step
			end

		elseif interpolation.t == 'cw' then
			if dir_end > dir_start then
				dir_end = dir_end - math.pi * 2
			end
			--print('dir:',dir_start,dir_end)
			local dir_len = dir_start - dir_end 
			local dir_step = dir_len / (num_points + 1)
			--print('dir_len',dir_len,'dir_step',dir_step)
			local dir = dir_start - dir_step
			for i=1,num_points do
				local xx = center[1] + r*math.cos( dir )
				local yy = center[2] + r*math.sin( dir )
				table.insert(self._points,{xx,yy})
				dir = dir - dir_step
			end

		else
			error('unexpected interpolation ' .. interpolation.t)
		end
	end
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

function Contour:dump( ... )
	local len = #self._points
	log.info('contour len',len)
	if self._points[1] then
		log.info('1:',self._points[1][1],self._points[1][2])
	end
	if self._points[len] then
		log.info(len .. ':',self._points[len][1],self._points[len][2])
	end
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