local min  = math.min
local setm = setmetatable

local limiter = require"lacord.util.session-limit".new
local logger  = require"lacord.util.logger"
local mutex   = require"lacord.util.mutex".new

local _ENV = {}

local WEAK_CACHE = {__mode = "v"}


function initialize_ratelimit_properties(state, options)
    state.bucket_names = {}
    state.ratelimit_data = {}
    state.routex = setm({}, {__index = function(t, k) local m = mutex(); t[k] = m return m end, __mode = "v"})
    state.buckets = {}
    state.global = limiter(50)
    state.global.name = "global"
    state.route_delay = options.route_delay and min(options.route_delay, 0) or 1
end

local function get_bucket(self, id, major_params)
    local buckets = self.buckets[id]
    if major_params == "" then
        if buckets then return buckets
        else
            buckets = limiter(self.ratelimit_data[id].limit)
            self.buckets[id] = buckets
            return buckets
        end
    else
        if buckets and buckets[major_params] then
            return buckets[major_params]
        else
            if buckets then
                local obj = limiter(self.ratelimit_data[id].limit)
                obj.name = "bucket-"..id
                buckets[major_params] = obj
                return obj
            else
                return logger.throw("lacord.api.request: Bucket id missing from cache.")
            end
        end
    end
end

_ENV.get_bucket = get_bucket

function handle_delay(self, delay, name, major_params, bucket, first_time, from_routex)
    if delay then
        local delay_s, delay_id, delay_limit = delay[1], delay[2], delay[3]

        if first_time then
            logger.debug("Creating new ratelimit: %s %s %s", delay_s, delay_id, delay_limit)
            if delay_id and delay_limit then
                self.bucket_names[name] = delay_id
                --local identifier = delay_id

                self.ratelimit_data[delay_id] = self.ratelimit_data[delay_id] or {limit = delay_limit, id = delay_id, delay = delay_s}

                if not self.buckets[delay_id] and major_params ~= "" then self.buckets[delay_id] = setm({}, WEAK_CACHE) end

                bucket = get_bucket(self, delay_id, major_params)

                bucket:enter()
            end
        elseif bucket.total ~= delay_limit then
            logger.warn("lacord.api: Ratelimit for %s (%s) has changed: %s -> %s", delay_id, name, bucket.total, delay_limit)
            local diff = bucket.total - delay_limit
            bucket.v = bucket.v - diff
            self.ratelimit_data[delay_id].limit = delay_limit
        end
        if bucket then bucket:exit_after(delay_s) end
    else
        logger.debug("lacord.api: There wasn't any ratelimit information when performing %s.", name)
        if bucket then bucket:exit_after(0) end
    end

    if from_routex then self.routex[name]:unlock() end
end

return _ENV