-- file: lua/backend-baidu.lua

local http = require 'http'
local backend = require 'backend'

local char = string.char
local byte = string.byte
local find = string.find
local sub = string.sub

local ADDRESS = backend.ADDRESS
local PROXY = backend.PROXY
local DIRECT_WRITE = backend.SUPPORT.DIRECT_WRITE

local SUCCESS = backend.RESULT.SUCCESS
local HANDSHAKE = backend.RESULT.HANDSHAKE
local DIRECT = backend.RESULT.DIRECT

local ctx_uuid = backend.get_uuid
local ctx_proxy_type = backend.get_proxy_type
local ctx_address_type = backend.get_address_type
local ctx_address_host = backend.get_address_host
local ctx_address_bytes = backend.get_address_bytes
local ctx_address_port = backend.get_address_port
local ctx_write = backend.write
local ctx_free = backend.free
local ctx_debug = backend.debug

local is_http_request = http.is_http_request

local flags = {}
local kHttpHeaderSent = 1
local kHttpHeaderRecived = 2

function wa_lua_on_flags_cb(ctx)
    return 0
end

function wa_lua_on_handshake_cb(ctx)
    local uuid = ctx_uuid(ctx)
    
    if ( ctx_address_port(ctx) == 80 or ctx_address_port(ctx) == 8080 ) then
        flags[uuid] = kHttpHeaderRecived
        return true
    end

    if flags[uuid] == kHttpHeaderRecived then
        return true
    end
    
    local res = nil

    if flags[uuid] ~= kHttpHeaderSent then
        local host = ctx_address_host(ctx)
        local port = ctx_address_port(ctx)
        

        res = 'CONNECT ' .. host .. ':' .. port ..' HTTP/1.1\r\n' ..
                    'Host: ' .. host .. ':' .. port .. '\r\n' ..
                    'Proxy-Connection: Keep-Alive\r\n'..
                    'Proxy-Authorization: Basic dWMxMC4xOTQuMTg3LjIyMDoxZjQ3ZDNlZjUzYjAzNTQ0MzQ1MWM3ZWU3ODczZmYzOA==\r\n\r\n'

        ctx_debug(ctx_address_host(ctx)..' '..res)

        ctx_write(ctx, res)
        flags[uuid] = kHttpHeaderSent
    end

    return false
end

function wa_lua_on_read_cb(ctx, buf)
    ctx_debug('wa_lua_on_read_cb')
    local uuid = ctx_uuid(ctx)
    if flags[uuid] == kHttpHeaderSent then
        flags[uuid] = kHttpHeaderRecived
        return HANDSHAKE, nil
    end
    return DIRECT, buf
end

function wa_lua_on_write_cb(ctx, buf)
    ctx_debug('wa_lua_on_write_cb')
    
    local host = ctx_address_host(ctx)
    local port = ctx_address_port(ctx)
    
    if ( port == 80 or port == 8080 ) then
            local index = find(buf, '/')
            local method = sub(buf, 0, index - 1)
            local rest = sub(buf, index)
            local s, e = find(rest, '\r\n')
            buf = method .. 'http://' .. host .. ':' .. port .. sub(rest, 0, e) ..
            'Proxy-Authorization: Basic dWMxMC4xOTQuMTg3LjIyMDoxZjQ3ZDNlZjUzYjAzNTQ0MzQ1MWM3ZWU3ODczZmYzOA==\r\n' ..
            sub(rest, e + 1)

            ctx_write(ctx, buf)
            return SUCCESS, nil
    end
    
    return DIRECT, buf
end

function wa_lua_on_close_cb(ctx)
    ctx_debug('wa_lua_on_close_cb')
    local uuid = ctx_uuid(ctx)
    flags[uuid] = nil
    ctx_free(ctx)
    return SUCCESS
end
