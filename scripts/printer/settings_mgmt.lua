local table_load = require 'table_load'
local json = require 'llae.json'
local log = require 'llae.log'

local settings = {}

settings._data = {}
settings._by_name = {}

local function set_value_default( data, val)
	data.value = val
end
local metatables = {}

metatables.string = { set_value = set_value_default }
metatables.number = { set_value = set_value_default }

metatables.integer = { }

function metatables.integer:set_value( val )
	self.value = math.floor(tonumber(val))
end

metatables.boolean = { }

function metatables.boolean:set_value( val )
	if (type(val)=='string') then
		val = (val == 'true') 
	end
	self.value = not not (val)
	--print('set value',val,self.value)
end

local list_mt = {}

function list_mt:get_values(  )
	return self.value
end
function list_mt:set_value( val )
	assert(type(val)=='table','invalid value ' .. tostring(val) .. ':' .. tostring(self.name))
	self.value = {}
	for _,v in ipairs(val) do
		table.insert(self.value,self:convert(v))
	end
end
function list_mt:add_value( val )
	table.insert(self.value,self:convert(val))
end

function list_mt:add_item(  )
	table.insert(self.value,self.value[#self.value] or 0)
end

function list_mt:remove_item( idx )
	table.remove(self.value,idx)
end


metatables.number_list = setmetatable({ is_list = true , element_type = 'number'},{__index=list_mt})
function metatables.number_list:convert( val )
	return tonumber(val)
end
metatables.string_list = setmetatable({ is_list = true , element_type = 'string'},{__index=list_mt})
function metatables.string_list:convert( val )
	return tostring(val)
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
	table_load.load_string( require 'printer.settings', functions )
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
			v.value = config[v.name]
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
	local data_file = io.open(file,'w+')
	data_file:write(json_data)
	data_file:close()
end

function settings:__index( name )
	return self:item(name).value
end

function settings:item( name )
	return (self._by_name[name] or error('unknown setting ' .. tostring(name)))
end

function settings:get_settings( page )
	local r = {}
	log.info('settings:get_settings',page)
	for _,v in ipairs(self._data) do
		if v.page == page then
			table.insert(r,v)
		end
	end
	return r
end

return setmetatable(settings,settings)