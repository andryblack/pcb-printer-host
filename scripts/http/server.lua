local class = require 'llae.class'
local web = require 'web.application'
local log = require 'llae.log'


local server = class(web)
server.sidebar = require 'http.view.sidebar'

function server:_init( settings )
	self._config = settings
	web._init(self)

	self.printer_api = require 'http.api.printer'

	self:set_fs_root(self._config.rootdir)
	local static = self:use(web.static('public',{extensions={'js','css','html','map','svg'}}))
	self:use(web.json())
	self:use(web.cookie())
	self:use(web.formparser())
	self:use(web.multipart())
	self:use(web.views('view',{ext='html',nocache=true}))

	self:get('/',function( request , reply)
		return reply:redirect('/home')
	end)

	local api = {
		printer = self.printer_api
	}
	
	for _,v in ipairs(self.sidebar) do
		self:get('/' .. v.name,function(req,res)
			return res:render('layout',{
				route = v.name,
				json = require 'llae.json',
				sidebar = self.sidebar,
				sidebar_active = v.name,
				content = v.name,
				printer = application.printer,
				printer_state = self.printer_api:get_state(),
				settings = application.printer.settings,
				api = api
			})
		end)
	end



	self.printer_api.make_routes( self )

	local files_api = require 'http.api.files'
	api.files = files_api
	files_api.make_routes( self )

	local pcb_api = require 'http.api.pcb'
	api.pcb = pcb_api
	pcb_api.make_routes( self )

	local settings = require 'http.view.settings'
	for _,v in ipairs(settings.sidebar) do
		self:get('/settings/' .. v.name,function( request, res )
			return res:render('settings',{
				route = v.name,
				json = require 'llae.json',
				sidebar = settings.sidebar, 
				sidebar_active = v.name,
				page = v.name,
				settings = settings,
			})
		end)
		self:post('/settings/' .. v.name,function( request , res)
			local data = {}
			if request.multipart then
				for _,v in ipairs(request.multipart) do
					data[v.name] = v.data
				end
			elseif request.form then
				data = request.form
			else 
				error('need data')
			end
			local json = require 'llae.json'
			log.info('settings:',v.name,json.encode(data))
			settings:apply(v.name,data)
			return res:render('settings',{
				route = v.name,
				json = require 'llae.json',
				sidebar = settings.sidebar, 
				sidebar_active = v.name,
				page = v.name,
				settings = settings,
			})
		end)
	end

	self:get('/settings',function( request , response )
		response:redirect('/settings/' .. settings.sidebar[1].name )
	end)
end


function server:start()
	self:listen{
		port=self._config.port or 1337,
		host=self._config.host or '127.0.0.1'
	}
	return true
end

return server

-- local server = {}

-- local http = require 'llae.http'
-- local url = require 'net.url'
-- local router = require 'router'
-- local json = require 'llae.json'

-- local class = require 'llae.class'


-- local template = require "resty.template"
-- template.caching(false)

-- local function readfile(path)
--     local file = io.open(path, "rb")
--     if not file then return nil end
--     local content = file:read "*a"
--     file:close()
--     return content
-- end

-- local function loadlua(path)
--     return readfile(package.root..'/http/template/'..path) or path
-- end

-- template.load = loadlua
-- template.print = function(v) return v end

-- local _wrap_req_mt = {}

-- server._http = http.createServer(function (req, res)
--   server:process_request(req,res)
-- end)


-- server.router = router.new()

-- local mime_by_ext = {
-- 	js = 'application/javascript',
-- 	css = 'text/css',
-- }

-- local Request = class(nil,'http.Request')

-- function Request:_init( req , resp )
-- 	self._req = req
-- 	self._resp = resp
-- 	self.content_type = req:get_header("Content-Type")
-- 	if self.content_type and 
-- 		self.content_type == 'application/json' then
-- 		self.json = assert(json.decode(self:read_body()))
-- 	end
-- end


-- function Request:read_body(  )
-- 	local data = ''
-- 	while true do
-- 		local d = self._req:read()
-- 		if not d then
-- 			return data
-- 		end
-- 		data = data .. d
-- 	end
-- 	return data
-- end


-- function Request:write_redirect( path  )
-- 	self._resp:set_header('Location',path)
-- 	self._resp:send_reply(301)
-- end

-- function Request:write_json( data  )
-- 	self._resp:set_header('Content-Type',"application/json")
-- 	self._resp:write(json.encode(data))
-- end

-- function Request:write_data( data, content_type )
-- 	self._resp:set_header('Content-Type',content_type)
-- 	self._resp:write(data)
-- end

-- function Request:write_template( name, params )
-- 	local view  = template.new(name)
-- 	self._resp:set_header('Content-Type',"text/html")
-- 	self._resp:write(view:render(params))
-- end

-- function server:process_request( req , res )
-- 	assert(req)
-- 	local uri = req:get_path()
-- 	local u = url.parse('http://localhost'..uri)
-- 	local content_type = req:get_header("Content-Type")
-- 	--print('prroces_request',req:get_method(),uri,content_type)


	
-- 	local request = Request.new( req , res )

	
-- 	local f,params = self.router:resolve(req:get_method(),u.path,u.query)
-- 	if not f then
-- 		local rfile = string.gsub(u.path,'%.%.','__')
-- 		local filename = application.config.http_root .. '/' .. rfile
-- 		local ext = string.match(u.path,'.*%.(.*)')
-- 		res:set_header('Content-Type',(ext and mime_by_ext[ext]) or 'binary')
-- 		self._http:send_static_file(req,res,filename)
-- 	else
-- 		for k,v in pairs(params) do
-- 			request[k] = v
-- 		end
-- 		local st,err = xpcall(f,debug.traceback,request)
-- 		if not st then
-- 			print(err)
-- 			request:write_data(tostring(err),'text/plain')
-- 			res:send_reply(500)
-- 		end
-- 		res:finish()
-- 	end
-- end

-- function server:start(  )
-- 	print('start http server at',application.config.addr,application.config.port)
-- 	self._http:listen(application.config.port, application.config.addr)
-- end

-- function server:stop(  )
-- 	self._http:stop()
-- end


-- function server:load_form_multipart( request )
-- 	local content_type = request.content_type
-- 	if not content_type then
-- 		error('empy Content-Type')
-- 	else
-- 		if content_type == 'application/x-www-form-urlencoded' then
-- 			local data = request:read_body()
-- 			print(data)
-- 			return url.parseQuery(data)
-- 		else
-- 			local multipart_handler = (require 'http.multipart');
-- 			local read = function (  )
-- 				return request._req:read()
-- 			end
-- 		    local multipart = multipart_handler.new(content_type,read)
-- 		    return assert(multipart:read())
-- 		end
-- 	end
-- end

-- function server:get( route, func )
-- 	self.router:get(route,func)
-- end

-- function server:post( route, func )
-- 	self.router:post(route,func)
-- end

-- server.printer_api = require 'http.api.printer'

-- server:get('/',function( request )
-- 	request:write_redirect('/home')
-- end)

-- local sidebar = require 'http.view.sidebar'
-- for _,v in ipairs(sidebar) do
-- 	server:get('/' .. v.name,function( request )
-- 		local ctx = { 
-- 			_req = request._req, 
-- 			json = json,
-- 			route = v.name, 
-- 			sidebar = sidebar, 
-- 			sidebar_active = v.name,
-- 			printer = application.printer,
-- 			printer_state = server.printer_api:get_state(),
-- 			settings = application.printer.settings,
-- 			api = server.printer_api
-- 		}
-- 		request:write_template('pages/' .. v.name .. '.html', ctx)
-- 	end)
-- end

-- local settings = require 'http.view.settings'
-- for _,v in ipairs(settings.sidebar) do
-- 	server:get('/settings/' .. v.name,function( request )
-- 		local ctx = { _req = request._req, 
-- 			route = v.name,
-- 			json = json, 
-- 			sidebar = settings.sidebar, 
-- 			sidebar_active = v.name,
-- 			page = v.name,
-- 			settings = settings }
-- 		request:write_template('settings.html', ctx)
-- 	end)
-- 	server:post('/settings/' .. v.name,function( request )
-- 		local data = server:load_form_multipart(request)
-- 		settings:apply(v.name,data)
-- 		local ctx = { _req = request._req, 
-- 			route = v.name,
-- 			json = json, 
-- 			sidebar = settings.sidebar, 
-- 			sidebar_active = v.name,
-- 			page = v.name,
-- 			settings = settings }
-- 		request:write_template('settings.html', ctx)
-- 	end)
-- end

-- server:get('/settings',function( request )
-- 	request:write_redirect('/settings/' .. settings.sidebar[1].name )
-- end)

-- server.printer_api.make_routes(server)


-- local files_api = require 'http.api.files'
-- files_api.make_routes( server )

-- local pcb_api = require 'http.api.pcb'
-- pcb_api.make_routes( server )


-- return server