local serial = require 'posix.serial'
local async = require 'llae.async'
local log = require 'llae.log'

local firmware = {}

local ACK = 0x79
local NACK = 0x1F
local SYNC = 0x7F

local CMD_GET = 0x00
local CMD_GO = 0x21
local CMD_WRITE = 0x31
local CMD_ERASE = 0x43
local CMD_EXT_ERASE = 0x44

local command_names = {
	[CMD_GET] = 'Get',
	[0x01] = 'Get Version',
	[0x02] = 'Get ID',
	[0x11] = 'Read Memory',
	[CMD_GO] = 'Go',
	[CMD_WRITE] = 'Write Memory',
	[CMD_ERASE] = 'Erase',
	[CMD_EXT_ERASE] = 'Extended erase',
	[0x63] = 'Write Protect',
	[0x73] = 'Write Unprotect',
	[0x82] = 'Readout Protect',
	[0x92] = 'Readout Unprotect',
}

local FLASH_BASE = 0x08000000
local WRITE_CHUNK = 256

local function xor_bytes( data )
	local cs = 0
	for i = 1, #data do
		cs = cs ~ string.byte(data, i)
	end
	return cs
end

function firmware:close()
	if self._serial then
		self._serial:close()
		self._serial = nil
	end
end

function firmware:update_status( status )
	self._status.status = status
end

function firmware:update_progress( progress )
	self._status.progress = progress
end


function firmware:read_byte( timeout_ms )
	timeout_ms = timeout_ms or 3000
	local remaining = math.ceil(timeout_ms / 10)
	while true do
		local data,err = self._serial:raw_read(1)
		if data and #data > 0 then
			return string.byte(tostring(data), 1)
		end
		remaining = remaining - 1
		if remaining <= 0 then
			log.error('failed read byte',err)
			error('serial read timeout')
		end
		async.pause(10)
	end
end

function firmware:read_exact( count, timeout_ms )
	timeout_ms = timeout_ms or 3000
	local remaining = math.ceil(timeout_ms / 10)
	local parts = {}
	local len = 0
	while len < count do
		local data = self._serial:raw_read(count - len)
		if data and #data > 0 then
			parts[#parts + 1] = tostring(data)
			len = len + #data
		end
		if len >= count then
			break
		end
		remaining = remaining - 1
		if remaining <= 0 then
			error('serial read timeout')
		end
		async.pause(10)
	end
	return table.concat(parts, '')
end

function firmware:expect_ack()
	local byte = self:read_byte()
	if byte ~= ACK then
		error(string.format('expected ACK (0x79), got 0x%02x', byte or 0))
	end
end

function firmware:send_cmd( cmd )
	self._serial:write(string.char(cmd, cmd ~ 0xFF))
	self:expect_ack()
end

function firmware:drain()
	log.info('start drain')
	while true do
		local data = self._serial:raw_read(1024)
		if not data or #data == 0 then
			break
		end
		log.info('drain',#data)
	end
	log.info('end drain')
end

function firmware:sync( max_attempts )
	max_attempts = max_attempts or 20
	for i = 1, max_attempts do
		log.info('sync attempt',i)
		local res,err = self._serial:write(string.char(SYNC))
		if not res then
			log.error('failed serial write',err)
		end
		local ok, byte = pcall(function()
			return self:read_byte(500)
		end)
		if ok and byte == ACK then
			log.info('response to sync command')
			async.pause(100)
			return true
		end
		async.pause(200)

		local res,err = self._serial:write(string.char(0x01,0xFE))
		if not res then
			log.error('failed serial write 2',err)
		end
		local ok, byte = pcall(function()
			return self:read_byte(500)
		end)
		if ok and byte == ACK then
			log.info('response to get version, sync completed')
			async.pause(100)
			self:drain()
			return true
		end
		async.pause(200)
	end
	return false,'sync failed'
end


function firmware:get_commands()
	self:send_cmd(CMD_GET)
	local n = self:read_byte()
	local payload = self:read_exact(n + 1)
	self:expect_ack()
	local version = string.byte(payload, 1)
	local commands = {}
	log.info('bootloader version', string.format('0x%02x',version), 'commands', #payload - 1)
	for i = 2, #payload do
		local cmd = string.byte(payload, i)
		commands[cmd] = true
		log.info(string.format('0x%02x',cmd),command_names[cmd])
	end
	return version, commands
end

function firmware:mass_erase_extended()
	self:send_cmd(CMD_EXT_ERASE)
	local payload = string.char(0xFF, 0xFF, 0x00)
	self._serial:write(payload)
	self:expect_ack()
end

function firmware:mass_erase_legacy()
	self:send_cmd(CMD_ERASE)
	self._serial:write(string.char(0xFF, 0x00))
	self:expect_ack()
end

function firmware:erase( commands )
	if commands[CMD_EXT_ERASE] then
		self:mass_erase_extended()
	elseif commands[CMD_ERASE] then
		self:mass_erase_legacy()
	else
		error('bootloader does not support erase')
	end
end

function firmware:write_memory( address, data )
	local pad = (4 - (#data % 4)) % 4
	if pad > 0 then
		data = data .. string.rep('\xFF', pad)
	end

	self:send_cmd(CMD_WRITE)

	local addr_bytes = string.pack('>I4', address)
	self._serial:write(addr_bytes .. string.char(xor_bytes(addr_bytes)))
	self:expect_ack()

	local payload = string.char(#data - 1) .. data
	self._serial:write(payload .. string.char(xor_bytes(payload)))
	self:expect_ack()
end

function firmware:go( address )
	self:send_cmd(CMD_GO)
	local addr_bytes = string.pack('>I4', address)
	self._serial:write(addr_bytes .. string.char(xor_bytes(addr_bytes)))
	self:expect_ack()
end

function firmware:flash_firmware( data )
	self:update_status('syncing')
	self:update_progress(0)

	self:drain()
	if not self:sync() then
		return false,'sync failed'
	end

	local _, commands = self:get_commands()
	self:update_status('erasing')
	self:erase(commands)

	local address = FLASH_BASE
	local offset = 1
	local written = 0

	self:update_status('writing')

	while offset <= #data do
		local chunk_len = math.min(WRITE_CHUNK, #data - offset + 1)
		local chunk = data:sub(offset, offset + chunk_len - 1)
		self:write_memory(address, chunk)
		written = written + chunk_len
		offset = offset + chunk_len
		address = address + chunk_len
		self:update_progress(written)
	end

	self:go(FLASH_BASE)
	return true
end

function firmware:flash( opts )
	local device = opts.device
	local data = opts.data
	self._status = opts.status

	self:update_status('connecting')

	local serial_connection, err = serial.open(device, { baudrate = 9600 })
	if not serial_connection then
		return false, 'failed to open serial device: ' .. tostring(err)
	end
	serial_connection:set_parity('even')
	self._serial = serial_connection
	

	local res,err = self:flash_firmware(data)
	if not res then
		self:update_status('error')
		return nil,err
	end

	self:update_status('done')
	self:close()

	return true
end

return firmware
