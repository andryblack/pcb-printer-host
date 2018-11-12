local r = {}

if args then

	local a = 1
	while args[a] do
		local k,v = string.match(args[a],'%-%-([^%s=]+)=([^%s]+)')
		if k and v then
			r[k] = v
			print('cli-arg',k,v)
		end
		a = a + 1
	end

end

return r