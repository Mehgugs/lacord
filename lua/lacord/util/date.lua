local compat = require"lacord.util.plcompat"
local uint = require"lacord.util.uint"

local os_time, os_date, os_difftime = os.time, os.date, os.difftime
local select = select
local type = type
local error = error
local getmetatable = getmetatable
local ipairs, next = ipairs, next
local ceil = math.ceil

local class = compat.class
local assert_arg = compat.assert_arg

local _ENV = {}

Date = class()
Date.Format = class()

--- Date constructor.
-- @param t this can be either
--
--   * `nil` or empty - use current date and time
--   * number - seconds since epoch (as returned by `os.time`). Resulting time is UTC
--   * `Date` - make a copy of this date
--   * table - table containing year, month, etc as for `os.time`. You may leave out year, month or day,
-- in which case current values will be used.
--   * year (will be followed by month, day etc)
--
-- @param ...  true if  Universal Coordinated Time, or two to five numbers: month,day,hour,min,sec
-- @function Date
function Date:_init(t,...)
    local time
    local nargs = select('#',...)
    if nargs > 2 then
        local extra = {...}
        local year = t
        t = {
            year = year,
            month = extra[1],
            day = extra[2],
            hour = extra[3],
            min = extra[4],
            sec = extra[5]
        }
    end
    if nargs == 1 then
        self.utc = select(1,...) == true
    end
    if t == nil or t == 'utc' then
        time = os_time()
        self.utc = t == 'utc'
    elseif type(t) == 'number' then
        time = t
        if self.utc == nil then self.utc = true end
    elseif type(t) == 'table' then
        if getmetatable(t) == Date then -- copy ctor
            time = t.time
            self.utc = t.utc
        else
            if not (t.year and t.month) then
                local lt = os_date('*t')
                if not t.year and not t.month and not t.day then
                    t.year = lt.year
                    t.month = lt.month
                    t.day = lt.day
                else
                    t.year = t.year or lt.year
                    t.month = t.month or (t.day and lt.month or 1)
                    t.day = t.day or 1
                end
            end
            t.day = t.day or 1
            time = os_time(t)
        end
    else
        error("bad type for Date constructor: "..type(t),2)
    end
    self:set(time)
end

--- set the current time of this Date object.
-- @int t seconds since epoch
function Date:set(t)
    self.time = t
    if self.utc then
        self.tab = os_date('!*t',t)
    else
        self.tab = os_date('*t',t)
    end
end

--- get the time zone offset from UTC.
-- @int ts seconds ahead of UTC
function Date.tzone (ts)
    if ts == nil then
        ts = os_time()
    elseif type(ts) == "table" then
        if getmetatable(ts) == Date then
            ts = ts.time
        else
            ts = Date(ts).time
        end
    end
    local utc = os_date('!*t',ts)
    local lcl = os_date('*t',ts)
    lcl.isdst = false
    return os_difftime(os_time(lcl), os_time(utc))
end

--- convert this date to UTC.
function Date:toUTC ()
    local ndate = Date(self)
    if not self.utc then
        ndate.utc = true
        ndate:set(ndate.time)
    end
    return ndate
end

--- convert this UTC date to local.
function Date:toLocal ()
    local ndate = Date(self)
    if self.utc then
        ndate.utc = false
        ndate:set(ndate.time)
--~         ndate:add { sec = Date.tzone(self) }
    end
    return ndate
end

--- set the year.
-- @int y Four-digit year
-- @class function
-- @name Date:year

--- set the month.
-- @int m month
-- @class function
-- @name Date:month

--- set the day.
-- @int d day
-- @class function
-- @name Date:day

--- set the hour.
-- @int h hour
-- @class function
-- @name Date:hour

--- set the minutes.
-- @int min minutes
-- @class function
-- @name Date:min

--- set the seconds.
-- @int sec seconds
-- @class function
-- @name Date:sec

--- set the day of year.
-- @class function
-- @int yday day of year
-- @name Date:yday

--- get the year.
-- @int y Four-digit year
-- @class function
-- @name Date:year

--- get the month.
-- @class function
-- @name Date:month

--- get the day.
-- @class function
-- @name Date:day

--- get the hour.
-- @class function
-- @name Date:hour

--- get the minutes.
-- @class function
-- @name Date:min

--- get the seconds.
-- @class function
-- @name Date:sec

--- get the day of year.
-- @class function
-- @name Date:yday


for _,c in ipairs{'year','month','day','hour','min','sec','yday'} do
    Date[c] = function(self,val)
        if val then
            assert_arg(1,val,"number")
            self.tab[c] = val
            self:set(os_time(self.tab))
            return self
        else
            return self.tab[c]
        end
    end
end

--- name of day of week.
-- @bool full abbreviated if true, full otherwise.
-- @ret string name
function Date:weekday_name(full)
    return os_date(full and '%A' or '%a',self.time)
end

--- name of month.
-- @int full abbreviated if true, full otherwise.
-- @ret string name
function Date:month_name(full)
    return os_date(full and '%B' or '%b',self.time)
end

--- is this day on a weekend?.
function Date:is_weekend()
    return self.tab.wday == 1 or self.tab.wday == 7
end

--- add to a date object.
-- @param t a table containing one of the following keys and a value:
-- one of `year`,`month`,`day`,`hour`,`min`,`sec`
-- @return this date
function Date:add(t)
    local old_dst = self.tab.isdst
    local key,val = next(t)
    self.tab[key] = self.tab[key] + val
    self:set(os_time(self.tab))
    if old_dst ~= self.tab.isdst then
        self.tab.hour = self.tab.hour - (old_dst and 1 or -1)
        self:set(os_time(self.tab))
    end
    return self
end

--- last day of the month.
-- @return int day
function Date:last_day()
    local d = 28
    local m = self.tab.month
    while self.tab.month == m do
        d = d + 1
        self:add{day=1}
    end
    self:add{day=-1}
    return self
end

--- difference between two Date objects.
-- @tparam Date other Date object
-- @treturn Date.Interval object
function Date:diff(other)
    local dt = self.time - other.time
    if dt < 0 then error("date difference is negative!",2) end
    return Date.Interval(dt)
end

--- long numerical ISO data format version of this date.
function Date:__tostring()
    local fmt = '%Y-%m-%dT%H:%M:%S'
    if self.utc then
        fmt = "!"..fmt
    end
    local t = os_date(fmt,self.time)
    if self.utc then
        return  t .. 'Z'
    else
        local offs = self:tzone()
        if offs == 0 then
            return t .. 'Z'
        end
        local sign = offs > 0 and '+' or '-'
        local h = ceil(offs/3600)
        local m = (offs % 3600)/60
        if m == 0 then
            return t .. ('%s%02d'):format(sign,h)
        else
            return t .. ('%s%02d:%02d'):format(sign,h,m)
        end
    end
end

--- equality between Date objects.
function Date:__eq(other)
    return self.time == other.time
end

--- ordering between Date objects.
function Date:__lt(other)
    return self.time < other.time
end

--- difference between Date objects.
-- @function Date:__sub
Date.__sub = Date.diff

--- add a date and an interval.
-- @param other either a `Date.Interval` object or a table such as
-- passed to `Date:add`
function Date:__add(other)
    local nd = Date(self)
    if Date.Interval:class_of(other) then
        other = {sec=other.time}
    end
    nd:add(other)
    return nd
end

Date.Interval = class(Date)

---- Date.Interval constructor
-- @int t an interval in seconds
-- @function Date.Interval
function Date.Interval:_init(t)
    self:set(t)
end

function Date.Interval:set(t)
    self.time = t
    self.tab = os_date('!*t',self.time)
end

local function ess(n)
    if n > 1 then return 's '
    else return ' '
    end
end

--- If it's an interval then the format is '2 hours 29 sec' etc.
function Date.Interval:__tostring()
    local t, res = self.tab, ''
    local y,m,d = t.year - 1970, t.month - 1, t.day - 1
    if y > 0 then res = res .. y .. ' year'..ess(y) end
    if m > 0 then res = res .. m .. ' month'..ess(m) end
    if d > 0 then res = res .. d .. ' day'..ess(d) end
    if y == 0 and m == 0 then
        local h = t.hour
        if h > 0 then res = res .. h .. ' hour'..ess(h) end
        if t.min > 0 then res = res .. t.min .. ' min ' end
        if t.sec > 0 then res = res .. t.sec .. ' sec ' end
    end
    if res == '' then res = 'zero' end
    return res
end

-- Discord related extensions to the pl.Date class --


--- Constructs a Date object from a discord snowflake id.
-- @param id either a `string` id or a `number` (encoded uint64) id.
-- @treturn Date object
function Date.fromSnowflake(id)
    return Date(uint.timestamp(id), true)
end

--- Converts a Date object to an ISO (8601) format timestamp.
-- @treturn string The timestamp
function Date:toISO()
	return os_date('!%FT%T', self.time) .. '+00:00'
end

--- Parses an ISO (8601) format timestamp into a numerical timestamp.
-- @string str the ISO string.
-- @treturn number The timestamp.
function Date.parseISO(str)
	local year, month, day, hour, min, sec, other = str:match(
		'(%d+)-(%d+)-(%d+).(%d+):(%d+):(%d+)(.*)'
	)
	return Date.parseTableUTC {
		day = day, month = month, year = year,
		hour = hour, min = min, sec = sec, isdst = false,
	}
end

--- Parses an ISO (8601) format timestamp into a date object.
-- @string str the ISO string.
-- @treturn Date object
function Date.fromDateTableUTC(str)
    return Date(Date.parseISO(str), true)
end

--- Alias for `Date(tbl, true)` which constructs a UTC date object.
-- @tab tbl A date table in the same format as the constructor.
-- @treturn Date object
function Date.fromDateTableUTC(tbl)
    return Date(tbl, true)
end

local months = {
	Jan = 1, Feb = 2, Mar = 3, Apr = 4, May = 5, Jun = 6,
	Jul = 7, Aug = 8, Sep = 9, Oct = 10, Nov = 11, Dec = 12
}

--- Parses a HTTP header into a Date object.
-- @string str The header string.
-- @treturn Date object
function Date.fromHeader(str)
	local day, month, year, hour, min, sec = str:match(
		'%a+, (%d+) (%a+) (%d+) (%d+):(%d+):(%d+) GMT'
	)
	return Date.fromDateTableUTC {
		day = day, month = months[month], year = year,
		hour = hour, min = min, sec = sec, isdst = false,
	}
end

local function offset()
    return os_difftime(os_time(), os_time(os_date('!*t')))
end

--- Parses a UTC date table into a timestamp.
-- @tab t A date table for `os.time`.
-- @treturn number The timestamp
function Date.parseTableUTC(t)
    return os_time(t) + offset()
end

--- Parses a HTTP header into a timestamp.
-- @string str the header string.
-- @treturn number The timestamp
function Date.parseHeader(str)
	local day, month, year, hour, min, sec = str:match(
		'%a+, (%d+) (%a+) (%d+) (%d+):(%d+):(%d+) GMT'
	)
	return Date.parseTableUTC{
		day = day, month = months[month], year = year,
		hour = hour, min = min, sec = sec, isdst = false,
	}
end

return _ENV