local files = {}
local file_api = (require 'llae').file

files.root = application.config.files

local icons_map = {
	gcode = 'layers',
    gbr = 'cpu',
    GTL = 'cpu',
    GBL = 'cpu',
    GBS = 'cpu',
    GTS = 'cpu',
    DRL = 'crosshair',
    xln = 'crosshair',
    GTO = 'lock',
    GKO = 'maximize'
}

local actions_map = {
    gcode = {icon='play',action='open_gcode'},
    gbr = {icon='edit',action='open_gerber'},
    xln = {icon='edit',action='open_drill'},
    GTL = {icon='edit',action='open_gerber'},
    GBL = {icon='edit',action='open_gerber'},
    GTS = {icon='edit',action='open_gerber'},
    GBS = {icon='edit',action='open_gerber'},
    DRL = {icon='edit',action='open_drill'},
    GTO = {icon='edit',action='open_gerber'},
    GKO = {icon='edit',action='open_gerber'}
}

function files:get_list( path )
	local dirs = {}
	local files = {}
	local folder = self.root .. '/' .. path
    local files_list,err = file_api.scandir(folder)
    print('scandir:',files_list,err)
    if not files_list then
        error(err or 'failed scandir')
    end
	for _,file in ipairs(files_list) do
        local name = file.name
        if name:sub(1,1) ~= "." then
            local f = folder..'/'..name
            print ("\t "..f)
            if file.isdir then
                table.insert(dirs,name)
            elseif file.isfile then
            	table.insert(files,file)
            end
        end
    end
    local res = {}
    table.sort(dirs)
    table.sort(files,function(a,b) return a.name < b.name end)
    for _,v in ipairs(dirs) do
    	table.insert(res,{
    		name = v,
    		dir = true
    		})
    end
    for _,v in ipairs(files) do
    	local ext = string.match(v.name,'.+%.(%w+)') or ''
    	table.insert(res,{
    		name = v.name,
    		ext = ext,
    		icon = icons_map[ext] or 'file',
            btn = actions_map[ext]
    	})
    end
    return res
end

function files:mkdir( path )
	local res,err = os.mkdir(self.root .. '/' .. path)
	if res then
		return {
			status = 'ok',
			path = path
		}
	else
		return {
			status = 'error',
			path = path,
			error = err
		}
	end
end

function files:remove( path )
    local res,err = os.remove(self.root .. '/' .. path)
    if res then
        return {
            status = 'ok',
            path = path
        }
    else
        return {
            status = 'error',
            path = path,
            error = err
        }
    end
end


local function receive_until( req, str )
	local data_parts = {}
	while (true) do
		local part = req:read()
		if not part then
			return nil,str .. ' not found'
		end
		
	end
end

function files:upload( req )
	
    local multipart_handler = (require 'http.multipart')
    local multipart = multipart_handler.new(req:get_header("Content-Type"),function()
        return req:read()
    end)
    
    local items = {}
    local root = self.root
    function multipart:on_item( item )
        multipart_handler.on_item(self,item)
        items[item.name] = item
        if item.attributes.filename then
            item.filename = item.attributes.filename
            item.tmpname = root .. '/.' .. item.filename .. '.tmp'
            local err = nil
            print('start write temp file:',item.tmpname)
            item.file,err = io.open(item.tmpname,'wb')
            if not item.file then
                return nil,err
            end
            function item:on_data(data,isend)
                local r,err = self.file:write(data)
                if not r then
                    return nil,err
                end
                if isend then
                    self.file:close()
                    print('end write temp file:',self.tmpname)
                end
                return true
            end
        end
        return true
    end

    local res,err = multipart:read()

    if not res then
        return {
            status = 'error',
            error = err
        }
    end
    if not items.file then
        return {
            status = 'error',
            error = 'file not found'
        }
    end
    
    local path = self.root .. '/' .. items.path.data

    local newname = items.file.filename
    print('rename',items.file.tmpname,path .. '/' .. newname)
    local res,err = os.rename(items.file.tmpname,path .. '/' .. newname)
    if not res then
        return {
            status = 'error',
            error = err
        }
    end
    return {
        status = 'ok',
        name = newname
    }
end


function files.make_routes( server )
    server:get('/api/files',function( request )
        request:write_json(files:get_list(request.path))
    end)
    server:post('/api/mkdir',function( request )
        request:write_json(files:mkdir(request.path))
    end)
    server:post('/api/upload',function( request )
        request:write_json(files:upload(request._req))
    end)
    server:post('/api/remove',function( request )
        request:write_json(files:remove(request.file))
    end)

    server:get('/files/*files_path',function( request )
        local ctx = { 
            _req = request._req, 
            json = require 'llae.json',
            route = 'files', 
            sidebar = require 'http.view.sidebar', 
            sidebar_active = 'files',
            printer = application.printer,
            printer_state = server.printer_api:get_state(),
            path = request.files_path,
            api = server.printer_api,
        }
        request:write_template('pages/files.html', ctx)
    end)
end

return files
