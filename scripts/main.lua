print(args[0])

local dir = string.match(args[0],'(.*)/.*')

if not math.pow then
	math.pow = function(base,p)
		return base ^ p
	end
end


local async = require 'llae.async'
local log = require 'llae.log'
local utils = require 'llae.utils'
local json = require 'llae.json'
local fs = require 'llae.fs'
local uv = require 'llae.uv'

local http_server = require 'http.server'
local printer = require 'printer.printer'
local path = require 'llae.path'
local video = require 'video'


local default_config = {
	addr = '0.0.0.0',
	port = 8080,
	files = 'local/files',
	rootdir = path.join(path.dirname(fs.exepath()),'..'),
	modules = 'local/share/pcb-laser-printer/?.lua',
	cmodules = 'no',
}

async.run(function()
	local res,err = xpcall(function()

		application = {}
		application.args = utils.parse_args(_G.args)


		local table_load = require 'table_load'

		local config = default_config
		if application.args.config then
			local f = fs.load_file(application.args.config)
			local lconfig = json.decode(f)
			for k,v in pairs(lconfig) do
				config[k] = v
			end
		end
		application.config = config
		package.path = package.path .. ';' .. config.modules
		package.cpath = package.cpath .. ';' .. config.cmodules

		local files_root = application.config.files

		if not fs.isdir(files_root) then
		    fs.mkdir(files_root)
		end

		if not fs.isdir(files_root .. '/.printer') then
		    fs.mkdir(files_root .. '/.printer')
		end

		application.http = http_server.new( config )
		application.http:start()

		application.printer = printer.new()
		application.printer:init()

		application.video = video.new()
		
		application.timer_sec = uv.timer.new()

		application.timer_sec:start(function()
			application.printer:on_timer(application.timer_sec)
			application.video:on_timer()
		end,1000,1000)

	end,
	debug.traceback)

	if not res then
		log.error('failed start printer')
		error(err)
	end

end)

