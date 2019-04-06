local class = require 'llae.class'

local Contour = require 'geom.contour'
local Geometry = require 'geom.geometry'

local Parser = class(nil,'gerber.Parser')
Parser._G = {}
Parser._EC = {}

local Region = require 'gerber.region'
local Aperture = require 'gerber.aperture'


function Parser:_init( )
	self._apertures ={}
	self._line_number = 0
	self._extended_command = nil	
	self._points = nil
	self._current_pos = {0,0}
	
	self._polarity = 'D'

	self._current_contour = nil
	self._current_aperture = nil
	self._mm_scale = 1.0
	self._aperture_macroses = {}
	--self._canvas = Geometry.new_collection()
end


function Parser:set_inches(  )
	self._mm_scale = 25.4
end

function Parser:set_millimeters(  )
	self._mm_scale = 1.0
end

function Parser:set_linear(  )
	
end

function Parser:on_ext_block_begin_end(  )
	if not self._extended_command then
		self._extended_command = { line = self._line_number }
	else
		self:on_extended_command(self._extended_command)
		self._extended_command = nil
	end
end

function Parser:on_block(  block )
	--print('block:',block)
	if self._extended_command then
		table.insert(self._extended_command,block)
	else
		self:on_function_code(block)
	end
end

function Parser:flush_current_contour(  )
	if not self._canvas then
		self._canvas = Geometry.new{}
	end
	if self._current_contour then
		if self._current_contour:num_points() == 1 then
			self._current_contour = nil
			return
		end
		if not self._current_aperture then
			error('current aperture dnt set')
		end
		self._canvas = self._current_aperture:draw_contour(self._canvas,self._current_contour)
		self._current_contour = nil
	end

end

function Parser:on_function_code( block )
	local gcode,data = string.match(block,'^G(%d+)(.*)')
	if gcode then
		gcode = tonumber(gcode)
		if not self._G[gcode] then
			error('unknown function code G' .. gcode .. ' at line ' .. self._line_number)
		end
		data = self._G[gcode](self,data)
		if not data or data=='' then
			return
		end
		block = data
	end
	
	local data,dcode = string.match(block,'^(.*)D(%d+)$')
	if dcode then
		local x,y 
		if data ~= '' then
			x = string.match(data,'X([%+%-]?%d+)')
			y = string.match(data,'Y([%+%-]?%d+)')
			if x then
				x = math.tointeger(x) * self._x_scale
			end
			if y then
				y = math.tointeger(y) * self._y_scale
			end
			if not x and not y then
				error('failed parse coordinate ' .. data)
			end
		end
		
		dcode = tonumber(dcode)
		if dcode == 1 then
			if self._region then
				self._region:draw(x,y)
			else
				if not self._current_contour then
					self._current_contour = Contour.new()
					self._current_contour:add_segment(self._current_pos[1],self._current_pos[2])
				end
				self._current_pos = { x or self._current_pos[1], y or self._current_pos[2] }
				self._current_contour:add_segment(self._current_pos[1],self._current_pos[2])
			end
		elseif dcode == 2 then
			if self._region then
				self._region:move(x,y)
			else
				self:flush_current_contour()
				self._current_pos = { x or self._current_pos[1], y or self._current_pos[2] }
			end
		elseif dcode == 3 then
			if self._region then
				error('not allowed in region')
			else
				self:flush_current_contour()
				self._current_pos = { x or self._current_pos[1], y or self._current_pos[2] }
				if not self._current_aperture then
					error('current aperture dnt set')
				end
				self._canvas = self._current_aperture:flash(self._canvas,self._current_pos[1],self._current_pos[2])
			end
		elseif dcode >= 10 then
			if self._region then
				error('not allowed in region')
			end
			self:select_aperture(dcode)
		else
			error('unexpected operation code D' .. dcode) 
		end
		return
	end
	if block == 'M02' then
		if self._region then
			error('not allowed in region')
		end
		self:finish()
		print('EOF')
		return
	elseif block == 'M00' then
		if self._region then
			error('not allowed in region')
		end
		self:finish()
		print('EOF')
		return
	end
	error('unexpected function code ' .. block)
end

function Parser:select_aperture( dcode )
	if not self._apertures[dcode] then
		error('not found aperture ' .. dcode)
	end
	self:flush_current_contour()
	self._current_aperture = self._apertures[dcode]
end

Parser._G[1] = function( self, data )
	self:set_linear()
	return data
end
Parser._G[2] = function( self, data )
	print('WARNING','Circular Interpolation not supported',self._line_number)
	--self:set_circular('cw')
	return ''
end
Parser._G[3] = function( self, data )
	print('WARNING','Circular Interpolation not supported',self._line_number)
	--self:set_circular('ccw')
	return ''
end
Parser._G[4]= function( self, data )
	print('comment:',data)
end
Parser._G[36]= function( self, data )
	self._region = Region.new(self,self._current_pos,self._polarity)
	--print('start region',self._polarity)
end
Parser._G[37]= function( self, data )
	if not self._region then
		error('region not started')
	end
	self._region:finish()
	--print('finish region',self._polarity)
	self._current_pos = self._region:get_last_pos()
	if self._canvas then
		if self._region._polarity == 'D' then
			--print('union geometry')
			self._canvas:union(self._region._geometry)
		else
			--print('difference geometry')
			self._canvas:difference(self._region._geometry)
		end
	else
		if self._region._polarity ~= 'D' then
			error('first region must be draw')
		end
		--print('assign first geometry',self._region._geometry:dump())
		self._canvas = self._region._geometry
	end
	--self._canvas:flush()
	self._region = nil
end
Parser._G[70]= function ( self , data )
	-- set units to inches
	self:set_inches()
end
Parser._G[71]= function ( self , data )
	-- set units to mm
	self:set_millimeters()
end
Parser._G[75]= function( self, data )
	print('G75:',data)
end
Parser._G[90]= function ( self , data )
	-- is just ok
end
Parser._G[54]= function ( self , data )
	print('G54:',data)
	local dcode = string.match(data,'^D(%d+)$')
	if not dcode then
		error('invalid G54 format')
	end
	dcode = tonumber(dcode)
	self:select_aperture(dcode)
end
function Parser:on_extended_command( cmd )
	if self._region then
		error('not allowed in region')
	end
	local code,data = string.match(cmd[1],'^(%u%u)(.+)')
	if not code then
		error('unknown extended command')
	end
	if not self._EC[code] then
		error('unexpected extended command (' .. code .. ')')
	end
	self._EC[code](self,data,cmd)
end

function Parser._EC.TF( self, data )
	print('attribute',data)
end
function Parser._EC.FS( self, data )
	local xi,xd,yi,yd = string.match(data,'^LAX(%d)(%d)Y(%d)(%d)$')
	if not xi then
		error('invalid FS format')
	end
	xi,xd,yi,yd = tonumber(xi),tonumber(xd),tonumber(yi),tonumber(yd)
	self._x_div = 1
	self._y_div = 1
	for _ = 1,xd do
		self._x_div = self._x_div * 10
	end
	for _ = 1,yd do
		self._y_div = self._y_div * 10
	end
	self._intscale = math.max(self._x_div,self._y_div)
	self._x_scale = self._intscale / self._x_div
	self._y_scale = self._intscale / self._y_div
end
function Parser._EC.MO( self, data )
	if data == 'IN' then
		self:set_inches()
	elseif data == 'MM' then
		self:set_millimeters()
	else
		error('invlid units ' .. data)
	end
end
function Parser._EC.LP( self, data )
	if data ~= 'C' and data ~= 'D' then
		error('invalid polarity')
	end
	self._polarity = data
end
function Parser._EC.AM( self, data , cmd )
	print('AM',data)
	local name = data
	local am = Aperture.macros( cmd , self._intscale)
	self._aperture_macroses[name] = am
end
function Parser._EC.AD( self, data )
	local code,name,other = string.match(data,'^D(%d+)(%w+),?(.*)$')
	if not code then
		error('invalid apperture format (' .. data .. ')')
	end
	code = tonumber(code)
	if code < 10 then
		error('invalid apperture index ' .. code)
	end
	if self._apertures[code] then
		error('dublicated apperture ' .. code)
	end
	local  aperture  = nil
	local  std_func = 'new_std_' .. name
	if Aperture[std_func] then
		aperture = Aperture[std_func](other,self._intscale)
	elseif self._aperture_macroses[name] then
		aperture = self._aperture_macroses[name]
	else 
		error('unknown apperture macros ' .. name)
	end
	if not aperture then
		error('failed create aperture ' .. name)
	end
	self._apertures[code] = aperture
end
function Parser._EC.LN( self, data )
	local name = string.match(data,'^(.+)$')
	self._load_name = name
	print('name:',name)
end
function Parser._EC.IN( self, data )
	local name = string.match(data,'^(.+)$')
	self._image_name = name
	print('image name:',name)
end
function Parser._EC.IP( self, data )
	local pol = string.match(data,'^(.+)$')
	self._image_plarity = pol
	print('image polarity:',pol)
end
function Parser._EC.TA( self, data )
	print('TA:',data)
end

function Parser:parse( line )
	self._line_number = self._line_number + 1
	local cl = string.match(line,'^(.*)\r$')
	if cl then
		line = cl
	end
	--print('parse','"'..line..'"')
	local res,err = pcall(function()
		while line ~= '' do
			local parsed = false
			local p,tail = string.match(line,'^(%%)(.*)$')
			if p then
				self:on_ext_block_begin_end()
				line = tail
				parsed = true
			end
			p,tail = string.match(line,'^(.+)%*(.*)$')
			if p then
				self:on_block(p)
				line = tail
				parsed = true
			end
			if not parsed then
				error('failed parse line "' .. line .. '"')
			end
		end
		-- for begb,block,endb in string.gmatch(line, '(%%?)(.+)%*(%%?)') do
  --      		self:on_block(begb=='%',block,endb=='%')
  --   	end
	end)
	if not res then
		error('failed parse line ' .. self._line_number .. '\n' .. err)
	end
end

function Parser:finish(  )
	self:flush_current_contour()
	self._canvas:flush()
end

function Parser:polygons( scale )
	self._canvas:flush()
	return self._canvas:export(((scale or 1.0) * self._mm_scale) / self._intscale)
end

function Parser:invert( bounds )
	local s = self._intscale / self._mm_scale
	local p = Geometry.new_polygon({
		{bounds:x()*s, bounds:y()*s },
		{bounds:x()*s, (bounds:y()+bounds:height())*s },
		{(bounds:x()+bounds:width())*s, (bounds:y()+bounds:height())*s },
		{(bounds:x()+bounds:width())*s, bounds:y()*s },
		
		})
	p:difference(self._canvas)
	self._canvas = p
end

function Parser:rm_circle( x,y,diam )
	local c = Geometry.new_circle(
		x / self._mm_scale * self._intscale,
		y / self._mm_scale * self._intscale,
		(diam/2) / self._mm_scale * self._intscale,32)
	self._canvas:difference(c)
	--self._canvas:flush()
end

return Parser