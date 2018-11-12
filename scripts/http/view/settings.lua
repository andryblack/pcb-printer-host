local sidebar = {
	prefix = '/settings/',
	{
		name = 'connection',
		text = 'Connection',
		icon = 'link'
	},
	{
		name = 'printer',
		text = 'Printer',
		icon = 'printer'
	},
	{
		name = 'pcb',
		text = 'PCB',
		icon = 'cpu'
	},
	{
		name = 'camera',
		text = 'Camera',
		icon = 'video'
	},
}

local html = require "resty.template.html"

local map_types = {
	string = 'text',
}

function map_types.select( config , id)
	local r = {'<select class="custom-select" id="'..id..'" name="'..config.name..'">'}
	for _,v in ipairs(config.values) do
		table.insert(r,html.option{value=tostring(v),selected=(v == config.value) and true or nil}(tostring(v)))
	end
	table.insert(r,'</select>')
	return table.concat(r,'\n')
end

function map_types.boolean( config , id)
	return html.input{ 
					id=id, class='form-check-input',
					type = 'checkbox', 
					--value = (config.value and 'checked' or ''),
					checked = config.value and true or nil,
					name = config.name}()
end

local swap_label = {
	['boolean'] = true
}

local form_controls = {
	['boolean'] = 'form-check'
}

function map_types.list( config, id )
	local r = {'<div class="form-group">'}
	local input_type = map_types[config.element_type] or 'text'
		
	for i,v in ipairs(config.value) do
		local iid = id .. '-' .. i
		table.insert(r,html.input{ 
					id=iid, class='form-control',
					name = config.name .. '[' .. (i) .. ']',
					type = input_type, 
					placeholder = config.placeholder, 
					value = v }())
	end
	table.insert(r,'</div>')
	return table.concat(r,'\n')
end

local settings = {}

settings.sidebar = sidebar



function settings:get_page( page_name )
	return application.printer.settings:get_settings( page_name )
end

function settings:format_input( config )
	local id = 'settings-contol-' .. config.name
	local input_type = map_types[config.control or config.type] or 'text'
	local swp = swap_label[config.control or config.type]
	local res = '<div class="'..(form_controls[config.control or config.type] or 'form-group')..'">\n'
	 
	if not swp then
		res = res .. html.label{ ['for'] = id }(config.descr)
	end
	res = res .. (type(input_type) == 'function' and input_type(config,id) or
				html.input{ 
					id=id, class='form-control',
					name = config.name,
					type = input_type, 
					placeholder = config.placeholder, 
					value = config.value }())

	if swp then
		res = res .. html.label{ ['for'] = id }(config.descr)
	end
			
	res = res .. '\n</div>'
	return res
end

local parse = {}

function parse.boolean( value )
	return value and ((value == 'checked') or (value == 'on'))
end

function settings:apply( page, data )
	for _,config in ipairs(self:get_page(page)) do
		local v = parse[config.control or config.type]
		if v then
			v = v(data[config.name])
		else
			v = data[config.name]
		end
		--print('apply',config.name,v)
		config:set_value(v)
	end
	application.printer:save_settings()
end

return settings