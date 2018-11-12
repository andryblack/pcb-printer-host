
local _M = {}

function _M.get_path( file )
	local dir = string.match(args[0],'(.*)/.*')
	return dir .. '/' .. file
end

function _M.load( file , env_)
	local env = env_ or {}
	local chunk = assert(loadfile(file,'t',env))
	chunk()
	return env
end

return _M