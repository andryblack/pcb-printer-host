local class = require 'llae.class'

local Contour = require 'geom.contour'
local Geometry = require 'geom.geometry'

local Dril = class(nil,'gerber.Dril')

function Dril:_init( )
	self._apertures ={}
	self._line_number = 0
	self._current_pos = {0,0}
	self._mm_scale = 1.0
	self._tools = {}
	self.points = {}
	self._scale = 1.0
	self._point_scale = 1.0
end


function Dril:set_inches(  )
	self._mm_scale = 25.4
	self._scale = self._mm_scale * self._point_scale
end

function Dril:set_millimeters(  )
	self._mm_scale = 1.0
	self._scale = self._mm_scale * self._point_scale
end


function Dril:on_block( block )
	local data = string.match(block,'^(.*);.*$')
	if data then
		block = data
	end
	if block == '' then
		return
	end
	local letter,code = string.match(block,'^(%u)(%d+)$')
	if letter then
		if letter == 'M' then
			self:process_M_code(tonumber(code))
		elseif letter == 'G' then
			self:process_G_code(tonumber(code))
		elseif letter == 'T' then
			self._active_tool = self._tools[code]
			if not self._active_tool then
				error('unknown tool ' .. code)
			end
		else
			error('invalid command')
		end
		return
	end
	if self._header then
		self:process_header(block)
		return
	end

	local x,y = string.match(block,'^X([%+%-]?%d+)Y([%+%-]?%d+)$')
	if x then
		x = math.tointeger(x) * self._scale
		y = math.tointeger(y) * self._scale
		table.insert(self.points,{x=x,y=y,tool=self._active_tool})
		return
	end

	local x1,y1,x2,y2 = string.match(block,'^X([%+%-]?%d+)Y([%+%-]?%d+)G85X([%+%-]?%d+)Y([%+%-]?%d+)$')
	if x1 then
		x = math.tointeger(x1) * self._scale
		y = math.tointeger(y1) * self._scale
		table.insert(self.points,{x=x,y=y,tool=self._active_tool})
		return
	end
	
	error('unexpected function code ' .. block)
end

function Dril:parse( line )
	self._line_number = self._line_number + 1
	local res,err = pcall(function()
		self:on_block(line)
	end)
	if not res then
		error('failed parse line ' .. self._line_number .. '\n' .. err)
	end
end

function Dril:process_header( block )
	if block == '%' then
		self._header = false
	else
		local a,b,c = string.match(block,'^(%u+),(%u+),?(.*)')
		if a then
			if a == 'INCH' then
				local fmt = string.match(c,'0+%.(0+)')
				if not fmt then
					error('invalid format ' .. c)
				end
				self._point_scale = 1.0 / math.pow(10,#fmt)
			
				self:set_inches()
				return
			elseif a == 'METRIC' then
				local fmt = string.match(c,'0+%.(0+)')
				if not fmt then
					error('invalid format ' .. c)
				end
				self._point_scale = 1.0 / math.pow(10,#fmt)

				self:set_millimeters()
				return
			elseif a == 'ICI' then
				return
			end
		end
		a,b = string.match(block,'^(%u+),(.*)$')
		if a then
			if a == 'FMAT' then
				print('set format',b)
				return
			end
		end
		local n,c,d = string.match(block,'^T(%d+)(%u)(.+)$')
		if n then
			self._tools[n] = self:parse_tool(c,d)
			return 
		end
		error('unknown header command ' .. block)
	end
end

function Dril:parse_tool( c, d )
	if c == 'C' then
		return {d=tonumber(d)*self._mm_scale}
	else
		error('unexpected tool definition ' .. c)
	end
end

function Dril:process_M_code( code )
	if code == 48 then
		self._header = true
	elseif code == 95 then
		self._header = false
	elseif code == 30 then
		self._end = true
	elseif code == 71 then
		-- Metric Measuring Mode
		self:set_millimeters()
	elseif code == 72 then
		-- Inch Measuring Mode
		self:set_inches()
	else
		error('unknown M code ' .. code)
	end
end

function Dril:process_G_code( code )
	if code == 5 then
		-- ok, dril mode
	elseif code == 90 then
		self._relative = false
	else
		error('unknown G code ' .. code)
	end
end

function Dril:finish( ... )
	-- body
end

return Dril