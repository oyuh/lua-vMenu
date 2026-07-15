-- Date helpers matching the C# DateTime behaviors the ban system depends on.
-- Newtonsoft serializes DateTime as timezone-less local time
-- "yyyy-MM-ddTHH:mm:ss[.fffffff]"; permanent bans are new DateTime(3000,1,1);
-- the vmenu.log writers stamp lines with dd-MM-yyyy HH:mm:ss.

local DateTime = {}

-- new DateTime(3000, 1, 1) exactly as Newtonsoft writes it.
DateTime.PERM_BAN_ISO = '3000-01-01T00:00:00'

function DateTime.now()
    return os.time()
end

function DateTime.to_iso(epoch)
    return os.date('%Y-%m-%dT%H:%M:%S', epoch)
end

-- DateTime.Now.AddHours(h), serialized. (We write whole-second precision;
-- the C# version appends 7 fraction digits, which parse_iso tolerates.)
function DateTime.add_hours_iso(epoch, hours)
    return DateTime.to_iso(epoch + math.floor(hours * 3600 + 0.5))
end

-- Accepts records written by both this rewrite and the C# original
-- (fractional seconds are parsed and dropped). Returns an os.time-style
-- table, or nil for garbage.
function DateTime.parse_iso(value)
    local year, month, day, hour, min, sec = tostring(value or ''):match('^(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+)')
    if not year then
        return nil
    end
    return {
        year = tonumber(year),
        month = tonumber(month),
        day = tonumber(day),
        hour = tonumber(hour),
        min = tonumber(min),
        sec = tonumber(sec),
    }
end

-- Upstream's permanent-ban check is record.bannedUntil.Year >= 3000.
function DateTime.is_permanent(iso)
    local parsed = DateTime.parse_iso(iso)
    return parsed ~= nil and parsed.year >= 3000
end

-- bannedUntil.Subtract(DateTime.Now).TotalSeconds. Unparseable dates count as
-- expired (upstream would have crashed on them; expiring is the safe reading).
-- Year 3000 is within os.time range on both Windows and Linux servers; the
-- pcall fallback only covers dates beyond that.
function DateTime.seconds_until(iso, now_epoch)
    local parsed = DateTime.parse_iso(iso)
    if not parsed then
        return 0
    end
    local ok, epoch = pcall(os.time, parsed)
    if not ok or epoch == nil then
        return DateTime.is_permanent(iso) and math.maxinteger or 0
    end
    return epoch - (now_epoch or os.time())
end

-- The [\t dd-MM-yyyy HH:mm:ss \t] stamp used by BanLog/KickLog.
function DateTime.log_stamp(epoch)
    return os.date('%d-%m-%Y %H:%M:%S', epoch)
end

return DateTime
