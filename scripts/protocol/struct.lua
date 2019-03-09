local _M = {}

function _M.readu32le( d,offset )
	local d = string.unpack('<I4',d,offset+1)
	return d, offset+4
end

function _M.readi32le( d,offset )
	local d = string.unpack('<i4',d,offset+1)
	return d, offset+4
end

function _M.readu16le( d,offset )
	local d = string.unpack('<I2',d,offset+1)
	return d, offset+2
end

function _M.readi16le( d,offset )
	local d = string.unpack('<i2',d,offset+1)
	return d, offset+2
end

function _M.readu8( d,o )
	return string.unpack('I1',d,o+1),o+1
end

function _M.readf32le( d,o )
	return string.unpack('<f',d,o+1),o+4
end

function _M.writeu32le( d )
	return string.pack('<I4',d)
end
function _M.writei32le( d )
	return string.pack('<i4',d)
end

function _M.writeu8( d )
	return string.pack('<I1',d)
end

function _M.writeu16le( d )
	return string.pack('<I2',d)
end
function _M.writei16le( d )
	return string.pack('<i2',d)
end

function _M.writef32le( d )
	return string.pack('<f',d)
end

local sizes = {u32=4,u16=2,u8=1}

local function reada(f,d,o,c)
	local r = {}
	for i=1,c do
		r[i],o = f(d,o)
	end
	return r,o
end

local function builda_def( f,d,c )
	assert(type(d)=='table')
	local r = {}
	assert(#d==c)
	for i=1,c do
		table.insert(r,f(d[i]))
	end
	return table.concat(r,'')
end

local builda = {}
function builda.u8( f, d, c)
	if type(d) == 'table' then
		return builda_def(f,d,c)
	end
	local r = string.char(string.byte(d,1,c))
	assert(#r == c)
	return r
end

local formats = {
}
function formats.u32( v )
	return string.format('0x%08x(%d)',v,v)
end
function formats.u16( v )
	return string.format('0x%04x',v)
end
function formats.u8( v )
	return string.format('0x%02x',v)
end



local formata = {}
function formata.u8( d , c)
	local r = {}
	local s = ''

	for _,v in ipairs(d) do
		if c.zeroterm and v==0 then
			break
		end
		table.insert(r,string.format('%02x',v))
		if v > 10 and v < 128 then
			s = s .. string.char(v)
		else
			s = s .. '.'
		end
		
	end
	if c.zeroterm then
		return '(' .. s .. ')'
	end
	return '[' .. table.concat(r,',')..'](' .. s .. ')'
end

local function format( d, c)
	local t = c[1]
	if type(d) == 'table' then
		if formata[t] then
			return formata[t](d,c)
		end
		local r = {}
		for _,v in ipairs(d) do
			table.insert(r,formats[t](v))
		end
		return '['..table.concat(r,',')..']' 
	end
	return formats[t](d)
end

local struct_mt = {}

function struct_mt:dump( o )
	local p = o or '\t'
	for _,v in ipairs(self._def) do
		if type(v[1]) == 'table' then
			print(p..'>'..v[2])
			self[v[2]]:dump(p..'\t')
		else
			local d = v.is_fill and '...' or format(self[v[2]],v)
			print(p..v[2],d)
		end
	end
end

function struct_mt:read( d,offset )
	local o = offset or 0
	local e = self._def.endian or 'le'
	for _,v in ipairs(self._def) do
		if type(v[1]) == 'table' then
			self[v[2]],o = _M.read(d,v[1],o)
		else
			local f = assert(_M['read'..v[1]] or _M['read'..v[1]..e])
			if v[3] then
				self[v[2]],o = reada(f,d,o,v[3])
			else
				self[v[2]],o = f(d,o)
			end
		end
	end
	return o
end

function struct_mt:build( )
	local r = {}
	local e = self._def.endian or 'le'
	for _,v in ipairs(self._def) do
		if type(v[1]) == 'table' then
			table.insert(r,self[v[2]]:build())
		else
			local f = assert(_M['write'..v[1]] or _M['write'..v[1]..e],'not found write ' .. v[1])
			local d = assert(self[v[2]])
			if v[3] then
				table.insert(r,(builda[v[1]] or  builda_def)(f,d,v[3]))
			else
				table.insert(r,f(d))
			end
		end
	end
	return table.concat(r,'')
end


struct_mt.__index = struct_mt

_M.format_bytes = function ( d )
	local a = {}
	for i=1,#d do
		local b = string.byte(d,i)
		table.insert(a,string.format('%02x',b))
	end
	return table.concat(a,',')
end

function _M.sizeof( s )
	local r = 0
	for _,v in ipairs(s) do
		local s = (type(v[1]) == 'table') and _M.sizeof(v[1]) or  sizes[v[1]]
		r = r + s * (v[3] or 1)
	end
	return r
end

function _M.offsetof( s , f )
	local r = 0
	for _,v in ipairs(s) do
		if f == v[2] then
			return r
		end
		local s = (type(v[1]) == 'table') and _M.sizeof(v[1]) or  sizes[v[1]]
		r = r + s * (v[3] or 1)
	end
	return nil
end

function _M.new( s , d)
	local r = {_def=s}
	if d then
		--print(s)
		for _,v in ipairs(s) do
			local fn = v[2]
			local iv = d[fn] or v.default
			--print('init struct field ' .. fn .. ' with ' .. iv)
			r[fn] = assert(iv,'need field ' .. fn)
		end
	end
	return setmetatable(r,struct_mt)
end

function _M.read( d, struct, offset )
	local r = _M.new(struct)
	local o = r:read(d,offset)
	return r,o
end


return _M