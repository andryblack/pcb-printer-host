local sidebar = {
	prefix = '/settings/',
	{
		name = 'connection',
		text = 'Connection',
		icon = 'link'
	},
	{
		name = 'firmware',
		text = 'Firmware',
		icon = 'hard-drive',
		custom = 'firmware'
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
	{
		name = 'ui',
		text = 'UI',
		icon = 'monitor'
	},
}


local map_types = {
	string = 'text',
}

local html = {}

local function element(name,tags)
	return function(value)
		local tagsv = {}
		for k,v in pairs(tags) do
			table.insert(tagsv,k .. '="' .. tostring(v) .. '"' )
		end
		return '<' .. name .. ' ' .. table.concat(tagsv,' ') .. ' >' .. (value or '') .. '</' .. name .. '>'
	end
end

function html.label(tags)
	return element('label',tags)
end
function html.input(tags)
	return element('input',tags)
end
function html.option(tags)
	return element('option',tags)
end


function map_types.select( config , id)
	local r = {'<select class="form-select" id="'..id..'" name="'..config.name..'">'}
	for _,v in ipairs(config.values) do
		local strval 
		if config.format then
			strval = string.format(config.format,v)
		else
			strval = tostring(v)
		end
		table.insert(r,html.option{value=strval,selected=(v == config.value) and true or nil}(strval))
	end
	table.insert(r,'</select>')
	return table.concat(r,'\n')
end

function map_types.boolean( config , id)
	local checked = config.value and ' checked' or ''
	return table.concat({
		'<div class="form-check form-switch">',
		'<input type="checkbox" class="form-check-input" id="', id,
			'" name="', config.name, '" value="true"', checked, '>',
		'<label class="form-check-label" for="', id, '">', config.descr, '</label>',
		'</div>'
	})
end

function map_types.list( config, id )
	local r = {'<div class="form-group list-edit">'}
	local input_type = map_types[config.element_type] or 'text'
		
	local len = #config.value
	for i,v in ipairs(config.value) do
		local iid = id .. '-' .. i
		table.insert(r,'<div class="input-group list-edit-item">')
		table.insert(r,html.input{ 
					id=iid, class='form-control',
					name = config.name .. '[' .. (i) .. ']',
					type = input_type, 
					placeholder = config.placeholder, 
					value = v }())
		if i==len then
			table.insert(r,'<button class="btn btn-outline-info list-edit-append" data-list-name="'..config.name..'" type="button" ><span data-feather="plus-square"></span></button>')
		end
		if len~=1 then
			table.insert(r,'<button data-item-idx="'..i..'" data-list-name="'..config.name..'" class="btn btn-outline-danger list-edit-remove" type="button" ><span data-feather="minus-square"></span></button>')
		end
		table.insert(r,'</div>')
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
	if config.type == 'boolean' then
		return map_types.boolean(config, id)
	end
	local input_type = map_types[config.control or config.type] or 'text'
	return table.concat{
			html.label{ ['for'] = id, class='form-label' }(config.descr),
			type(input_type) == 'function' and input_type(config,id) or
				html.input{ 
					id=id, class='form-control',
					name = config.name,
					type = input_type, placeholder = config.placeholder, 
					value = config.value }()
		}
end


function settings:apply( page, data )
	for _,config in ipairs(self:get_page(page)) do
		if config.type == 'boolean' then
			config:set_value(data[config.name] ~= nil and data[config.name] or false)
		else
			config:set_value(data[config.name])
		end
	end
	application.printer:save_settings()
end

return settings