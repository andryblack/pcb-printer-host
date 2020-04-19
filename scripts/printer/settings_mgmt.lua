local table_load = require 'table_load'
local json = require 'llae.json'

local settings = {}

settings._data = {}
settings._by_name = {}

local function set_value_default( data, val)
	data.value = val
end
local metatables = {}

metatables.string = { set_value = set_value_default }

metatables.number = {}
function metatables.number:set_value( val )
	self.value = tonumber(val)
end

metatables.number.parse = tonumber

metatables.integer = { }

function metatables.integer:set_value( val )
	self.value = math.floor(tonumber(val))
end

function metatables.integer.parse( val )
	return math.floor(tonumber(val))
end

metatables.boolean = { }

function metatables.boolean:set_value( val )
	if (type(val)=='string') then
		val = (val == 'true') 
	end
	self.value = not not (val)
	--print('set value',val,self.value)
end

metatables.number_list = { is_list = true , element_type = 'number'}
function metatables.number_list:get_values(  )
	return self.value
end
function metatables.number_list:set_value( val )
	assert(type(val)=='table')
	self.value = val
end
function metatables.number_list:add_value( val )
	table.insert(self.value,val)
end

for _,v in pairs(metatables) do
	v.__index = v
end

local functions = {}
function functions:__index( name )
	return function( data )
		data.type = name,
		table.insert(settings._data,setmetatable(data,assert(metatables[name])))
	end
end
setmetatable(functions,functions)

function settings:init( )
	table_load.load( package.root .. '/printer/settings.lua', functions )
	for _,v in ipairs(self._data) do
		v.value = v.default
		self._by_name[v.name] = v
	end
end


function settings:load( file )
	local data_file = io.open(file,'r')
	if not data_file then
		return false
	end
	local data = data_file:read('*a')
	data_file:close()
	local config = assert(json.decode(data))
	for _,v in ipairs(self._data) do
		if config[v.name] then
			v.value = (v.parse and v.parse(config[v.name])) or config[v.name]
		end 
	end
	return true
end

function settings:store( file )
	local data = {}
	for _,v in ipairs(self._data) do
		if v.value ~= v.default then
			data[v.name] = v.value
		end
	end
	local json_data = json.encode(data)
	local data_file = assert(io.open(file,'w+'))
	data_file:write(json_data)
	data_file:close()
end

function settings:__index( name )
	return (self._by_name[name] or error('unknown setting ' .. name)).value
end

function settings:get_settings( page )
	local r = {}
	for _,v in ipairs(self._data) do
		if v.page == page then
			table.insert(r,v)
		end
	end
	return r
end

return setmetatable(settings,settings)