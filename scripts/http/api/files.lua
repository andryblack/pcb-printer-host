local files = {}
local lpath = require 'llae.path'
local class = require 'llae.class'
local fs = require 'llae.fs'
local log = require 'llae.log'
local file_api = (require 'llae').file
local azip = require 'archive.zip'

files.root = application.config.files


local data_reader = class()

function data_reader:_init(data)
    self._data = data
    self._pos = 0
end

function data_reader:read(size)
    if self._pos >= #self._data then
        return nil,nil
    end
    local ch = self._data:sub(self._pos+1,self._pos+1+size-1)
    self._pos = self._pos + size
    return ch
end

function data_reader:seek(pos)
    self._pos = pos
end

function data_reader:close()
end

local icons_map = {
    gbr = 'cpu',
    GTL = 'cpu',
    GBL = 'cpu',
    GBS = 'cpu',
    GTS = 'cpu',
    DRL = 'crosshair',
    xln = 'crosshair',
    drl = 'crosshair',
    GTO = 'lock',
    GKO = 'maximize'
}

local actions_map = {
    gbr = {icon='edit',action='open_gerber'},
    drl = {icon='edit',action='open_drill'},
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
    local folder = lpath.join(self.root , path )
    local files_list,err = fs.scandir(folder)
    log.info('scandir:',files_list,err,folder)
    if not files_list then
        return {
            status = 'error',
            path = path,
            error = err
        }
    end
    for _,file in ipairs(files_list) do
        local name = file.name
        if name:sub(1,1) ~= "." then
            local f = lpath.join(folder,name)
            log.info ("\t "..f)
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
        local ext = lpath.extension(v.name) or ''
        table.insert(res,{
            name = v.name,
            ext = ext,
            icon = icons_map[ext] or 'file',
            btn = actions_map[ext]
        })
    end
    return  {
            status = 'ok',
            data = res
        }
end

function files:mkdir( path )
    local res,err = fs.mkdir(lpath.join(self.root, path))
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
    local filepath = lpath.join(self.root ,path)
    log.info( 'remove',filepath )
    if fs.isdir(filepath) then
        fs.rmdir_r(filepath)
        return {
            status = 'ok',
            path = path
        }
    end
    local res,err = fs.unlink(filepath)
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


function files:upload( req )

    if not req.multipart then
        return {
            status = 'error',
            error = 'need multipart'
        }
    end

    local file_part
    local path_part

    for _,v in ipairs(req.multipart) do
        log.info('data:',v.name,v.filename,#v.data)
        if v.name == 'file' then
            file_part = v
            log.info('found file:',v.filename)
        elseif v.name == 'path' then
            path_part = v
            log.info('found path:',v.data)
        end
    end

    if not file_part then
        return {
            status = 'error',
            error = 'need file'
        }
    end
    if not path_part then
        return {
            status = 'error',
            error = 'need path'
        }
    end

    local filepath = lpath.join(self.root , path_part.data , file_part.filename)
    while fs.isfile(filepath) or fs.isdir(filepath) do
        local a,b,c = string.match(filepath,'(.*)%-(%d+)%.(.*)')
        if not a then
            a,b = string.match(filepath,'(.*)%-(%d+)')
            c = 'file'
        end
        if a then
            filepath = a .. '-' .. (tonumber(b)+1) .. '.' .. c
        else
            a,b = string.match(filepath,'(.*)%.(.*)')
            if a then
                filepath = a .. '-1.' .. b
            else
                filepath = filepath .. '-1'
            end 
        end
    end

    if string.lower (lpath.extension(filepath)) == 'zip' then
        log.info('write zip file')
        local dirname = filepath:sub(1,-5)
        while fs.isdir(dirname) do
            local a,b = string.match(filepath,'(.*)%-(%d+)')
            if a then
                dirname = a .. '-' .. (tonumber(b)+1) 
            else
                dirname = dirname .. '-1'
            end
        end
        fs.mkdir(dirname)

        local z = azip.new(data_reader.new(file_part.data),#file_part.data)
        local files = {}
        assert(z:scan( function(fn)
            if fn:sub(-1) ~= '/' then
                --log.info('found file',fn)
                table.insert(files,fn)
            end
        end))
        for _,v in ipairs(files) do

            local cf = assert(z:open_file(v))
            local dest_fn = lpath.join(dirname,v)
            log.debug('write file',dest_fn,type(d))
            fs.mkdir_r(lpath.dirname(dest_fn))
            fs.unlink(dest_fn)
            local f = fs.open(dest_fn,fs.O_WRONLY|fs.O_CREAT)
            while true do
                local d,e = cf:read(1024*4)
                if not d then
                    break
                end
                f:write(d)
            end
            cf:close(true)
            f:close()
        end
        z:close()

        return {
            status = 'ok',
            name = lpath.basename(dirname)
        }
    else
        fs.write_file(filepath, file_part.data)
    end

    return {
        status = 'ok',
        name = lpath.basename(filepath)
    }
end


function files.make_routes( server )
    server:get('/api/files',function( request , res )
        res:json(files:get_list(request.query.path))
    end)
    server:post('/api/mkdir',function( request, res )
        res:json(files:mkdir(request.query.path))
    end)
    server:post('/api/upload',function( request, res )
        res:json(files:upload(request))
    end)
    server:post('/api/remove',function( request , res)
        res:json(files:remove(request.query.file))
    end)

    server:get('/files/:files_path',function( req, res )
        log.info('req',req.params.files_path)
        return res:render('layout',{
                route = 'files',
                json = require 'llae.json',
                sidebar = server.sidebar,
                sidebar_active = 'files',
                content = 'files',
                printer = application.printer,
                path = req.params.files_path,
                printer_state = server.printer_api:get_state(),
            })
    end)
end

return files