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
	self._point_scale = 1.0/10000
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
	local data,comment = string.match(block,'^(.*);(.*)$')
	if data then
		block = data
	end
	if block == '' then
		if comment and comment ~= '' then
			self:process_comment(comment)
		end
		return
	end

	if self._header then
		self:process_header(block)
		return
	end


	local letter,code = string.match(block,'^(%u)(%d+)$')
	if letter then
		if letter == 'M' then
			self:process_M_code(tonumber(code))
		elseif letter == 'G' then
			self:process_G_code(tonumber(code))
		elseif letter == 'T' then
			self._active_tool = self._tools[code] or self._tools[tonumber(code)]
			if not self._active_tool and code~='0' and code~='00' then
				error('unknown tool ' .. code)
			end
		elseif letter == 'X' then
			local x = self:parse_point(code)
			local y = self.points[#self.points].y
			table.insert(self.points,{x=x,y=y,tool=self._active_tool})
		elseif letter == 'Y' then
			local y = self:parse_point(code)
			local x = self.points[#self.points].x
			table.insert(self.points,{x=x,y=y,tool=self._active_tool})
		else
			error('invalid command')
		end
		return
	end
	
	local x,y = string.match(block,'^X([%+%-]?%d+)Y([%+%-]?%d+)$')
	if x then
		x = self:parse_point(x)
		y = self:parse_point(y)
		table.insert(self.points,{x=x,y=y,tool=self._active_tool})
		return
	end

	local x,y = string.match(block,'^X([%+%-]?[%d%.]+)Y([%+%-]?[%d%.]+)$')
	if x then
		x = self:parse_point(x)
		y = self:parse_point(y)
		table.insert(self.points,{x=x,y=y,tool=self._active_tool})
		return
	end

	local x1,y1,x2,y2 = string.match(block,'^X([%+%-]?%d+)Y([%+%-]?%d+)G85X([%+%-]?%d+)Y([%+%-]?%d+)$')
	if x1 then
		x = self:parse_point(x1) 
		y = self:parse_point(y1) 
		x2 = self:parse_point(x2)
		y2 = self:parse_point(y2)
		table.insert(self.points,{x=x,y=y,tool=self._active_tool,x2=x2,y2=y2})
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

function Dril:process_comment( block )
	if not self._header then
		return
	end
	local k,v = string.match(block,'^([%u_]+)=(.+)$')
	if k then
		print('comment:',k,v)
		if k=='FILE_FORMAT' then
			local p,d = string.match(v,'(%d):(%d)')
			if p then
				self._point_width = math.tointeger(p) + math.tointeger(d)
				self._point_scale = 1.0 / math.pow(10,math.tointeger(d))
				print('scale from comment:',p,self._point_scale)
				self._point_scale_from_comment = true
			end
		end
	end
end

function Dril:parse_point( str_val )
	if self._point_mode == 'LZ' then
		str_val = str_val .. string.rep('0',self._point_width - #str_val)
	end
	return math.tointeger(str_val) * self._scale
end

function Dril:process_header( block )
	if block == '%' then
		self._header = false
	else
		local a,b,c = string.match(block,'^(%u+),(%u+),?(.*)')
		if a then
			if a == 'INCH' then
				if c and c ~= '' then
					local fmt = string.match(c,'0+%.(0+)')
					if not fmt then
						error('invalid format ' .. c)
					end
					self._point_scale = 1.0 / math.pow(10,#fmt)
				elseif b == 'LZ' then
					if not self._point_scale_from_comment then
						error( 'not found point scale' )
					end
					self._point_mode = 'LZ'
					print('set point mode',b)
				else
					error('invalid format ' .. a .. b .. c)
				end
			
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
			error('unknown header command ' .. a)
		end
		a = string.match(block,'^(%u+)$')
		if a then
			if a == 'INCH' then
				self:set_inches()
				return
			end
			error('unknown header command ' .. a)
		end
		local n,d = string.match(block,'^T(%d+).*C([%d%.]+)$')
		if n then
			print('tool',n,d)
			local tool = {d=tonumber(d)*self._mm_scale}
			self._tools[n] = tool
			self._tools[tonumber(n)]=tool
			return 
		end
		
		error('unknown header command ' .. block)
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