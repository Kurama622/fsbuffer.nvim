local format = {}
local ffi = require("ffi")

ffi.cdef([[
typedef unsigned int uid_t;

struct passwd {
    char   *pw_name;       /* username */
    char   *pw_passwd;     /* user password */
    uid_t   pw_uid;        /* user ID */
    unsigned int pw_gid;   /* group ID */
    char   *pw_gecos;      /* user information */
    char   *pw_dir;        /* home directory */
    char   *pw_shell;      /* shell program */
};

struct passwd *getpwuid(uid_t uid);
]])

format.permissions = function(mode)
	local bit = require("bit")
	local function formatSection(r, w, x)
		return table.concat({
			bit.band(mode, r) ~= 0 and "r" or "-",
			bit.band(mode, w) ~= 0 and "w" or "-",
			bit.band(mode, x) ~= 0 and "x" or "-",
		})
	end

	return table.concat({
		formatSection(0x100, 0x080, 0x040),
		formatSection(0x020, 0x010, 0x008),
		formatSection(0x004, 0x002, 0x001),
	})
end

format.size = function(size)
	local units = {
		{ limit = 1024 * 1024 * 1024, unit = "G" },
		{ limit = 1024 * 1024, unit = "M" },
		{ limit = 1024, unit = "K" },
		{ limit = 0, unit = "B" },
	}

	for _, unit in ipairs(units) do
		if size > unit.limit then
			local converted = unit.limit > 0 and size / unit.limit or size
			return string.format("%.2f%s", converted, unit.unit)
		end
	end
	return string.format("%.2f%s", size, "B")
end

format.username = function(uid)
	local pw = ffi.C.getpwuid(uid)
	if pw == nil then
		return nil
	end
	return ffi.string(pw.pw_name)
end

format.friendly_time = function(timestamp)
	local now = os.time()
	local diff = now - timestamp
	if diff < 0 then
		return os.date("%Y %b %d %H:%M", timestamp)
	elseif diff < 60 then
		return string.format("%d secs ago", diff)
	elseif diff < 3600 then
		return string.format("%d mins ago", math.floor(diff / 60))
	elseif diff < 86400 then
		return string.format("%d hours ago", math.floor(diff / 3600))
	elseif diff < 86400 * 14 then -- two weeks show "X days ago"
		return string.format("%d days ago", math.floor(diff / 86400))
	else
		return os.date("%Y %b %d", timestamp)
	end
end
return format
