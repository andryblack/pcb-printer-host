local class = require 'middleclass'
local llae = require 'llae'


local Task = class('Task')

function Task:initialize( func )
	self._coro = coroutine.create(func)
	self._timer = llae.newTimer()
	self._complete = false
end

function Task:run(  )
	self._timer:start(function(  )
		self:on_timer()
	end,0,0)
end

function Task:on_timer( )
	local status,err = coroutine.resume(self._coro)
	if not status then
		self:on_error( err )
		self._timer:stop()
	elseif coroutine.status(self._coro) == 'dead' then
		self:on_complete()
		self._timer:stop()
	else
		self:run()
	end
end

function Task:on_error( err )
	-- body
end

function Task:on_complete(  )
	-- body
end

return Task
