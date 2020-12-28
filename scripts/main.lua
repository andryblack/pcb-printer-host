print(args[0])

local dir = string.match(args[0],'(.*)/.*')

if not math.pow then
	math.pow = function(base,p)
		return base ^ p
	end
end

package.path = dir .. '/?.lua'

package.root = dir

require 'base'
local llae = require 'llae'
llae.set_handler()
local timer_sec = llae.newTimer()

local function funcion_test( a,b,c )
	
end


local main_coro = coroutine.create(function()
	local res,err = xpcall(function()

		application = {}
		application.args = require 'cli_args'


		local table_load = require 'table_load'
		local config = table_load.load(table_load.get_path('default_config.lua'),{
			scripts_root = dir,
			lua = _G
		})
		if application.args.config then
			config = table_load.load(application.args.config,config)
		end
		application.config = config
		package.path = package.path .. ';' .. config.modules
		package.cpath = package.cpath .. ';' .. config.cmodules

		local files_root = application.config.files

		if not os.isdir(files_root) then
		    os.mkdir(files_root)
		end

		if not os.isdir(files_root .. '/.printer') then
		    os.mkdir(files_root .. '/.printer')
		end

		application.http = require 'http.server'
		application.http:start()

		application.printer = require 'printer.printer'
		application.printer:init()

		application.video = require 'video'
		application.video:init()
		
		timer_sec:start(function()
			application.printer:on_timer(timer_sec)
			application.video:on_timer()
		end,1000,1000)

	end,
	debug.traceback)

	if not res then
		print('failed start printer')
		error(err)
	end

end)

local res,err = coroutine.resume(main_coro)
if not res then
	print('failed main thread',err)
	error(err)
end

llae.run()
timer_sec:stop()
application.http:stop()
application.printer:stop()

application = nil

print('stop')
collectgarbage('collect')
llae.dump()
