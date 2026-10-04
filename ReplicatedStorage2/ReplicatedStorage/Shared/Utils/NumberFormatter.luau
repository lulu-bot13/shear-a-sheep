local MAX_VALUE_PLACEHOLDER = `♾️` -- when max value is reached, this will display instead

--[[
This module will convert large numbers into a readable string, e.g. 100000000 > 100M.
This is great for currency systems & leaderstats!
USE EXAMPLE:
local Format = require(PATH_TO_MODULE)
local number = 100000
local convertedNumber = Format(number)
print(convertedNumber) -- 100k will be printed
]]

-- do not touch these values unless you have a good reason to
local MIN_VALUE = 1_000
local MAX_VALUE = 1e306

local cashSuffixes = {
	"k",
	"m",
	"b",
	"t",
	"qd",
	"qn",
	"sx",
	"sp",
	"oc",
	"no",
	".D",
	"u.D",
	"d.D",
	"t.D",
	"qd.D",
	"qn.D",
	"sx.D",
	"sp.D",
	"oc.D",
	"no.D",
	".V",
	"u.V",
	"d.V",
	"t.V",
	"qd.V",
	"qn.V",
	"sx.V",
	"sp.V",
	"oc.V",
	"no.V",
	".T",
	"u.T",
	"d.T",
	"t.T",
	"qd.T",
	"qn.T",
	"sx.T",
	"sp.T",
	"oc.T",
	"no.T",
	".Qd",
	"u.Qd",
	"d.Qd",
	"t.Qd",
	"qd.Qd",
	"qn.Qd",
	"sx.Qd",
	"sp.Qd",
	"oc.Qd",
	"no.Qd",
	".Qn",
	"u.Qn",
	"d.Qn",
	"t.Qn",
	"qd.Qn",
	"qn.Qn",
	"sx.Qn",
	"sp.Qn",
	"oc.Qn",
	"no.Qn",
	".Sx",
	"u.Sx",
	"d.Sx",
	"t.Sx",
	"qd.Sx",
	"qn.Sx",
	"sx.Sx",
	"sp.Sx",
	"oc.Sx",
	"no.Sx",
	".Sp",
	"u.Sp",
	"d.Sp",
	"t.Sp",
	"qd.Sp",
	"qn.Sp",
	"sx.Sp",
	"sp.Sp",
	"oc.Sp",
	"no.Sp",
	".Oc",
	"u.Oc",
	"d.Oc",
	"t.Oc",
	"qd.Oc",
	"qn.Oc",
	"sx.Oc",
	"sp.Oc",
	"oc.Oc",
	"no.Oc",
	".No",
	"u.No",
	"d.No",
	"t.No",
	"qd.No",
	"qn.No",
	"sx.No",
	"sp.No",
	"oc.No",
	"no.No",
	"C", -- maximum possible value is 999C due to roblox limitation of ~1.8e308
}

-- precompute 1000^i values for each suffix index
local thousandPowers = {}
for i = 1, #cashSuffixes do
	thousandPowers[i] = 1000 ^ i
end

local numberFormatter = {}

function numberFormatter:Format(givenValue: number | string, NUMBER_OF_DECIMALS: number?)
	if not NUMBER_OF_DECIMALS then
		NUMBER_OF_DECIMALS = 2
	end
	local DECIMAL_EXPONENT = 10 ^ NUMBER_OF_DECIMALS

	local value = tonumber(givenValue)

	-- try to return early if possible, we want a valid number under 1000 & less than MAX_VALUE
	if value == nil then
		warn(`Value passed was not a number: {givenValue}`)
		return
	elseif value < 0 then
		return `null`
	elseif value < 100 then
		return `{math.round(value * DECIMAL_EXPONENT) / DECIMAL_EXPONENT}`
	elseif value < MIN_VALUE then
		return `{math.round(value)}`
	elseif value >= MAX_VALUE or value == math.huge then
		return MAX_VALUE_PLACEHOLDER
	end

	-- get order of magnitude
	local mag = math.floor(math.log10(value) / 3)

	-- clamp to max suffix to avoid overflow or nan
	local suffixIndex = math.min(mag, #cashSuffixes)

	-- create shortened number by scaling it down & rounding to DECIMAL_EXPONENT
	local short = math.floor(value / thousandPowers[suffixIndex] * DECIMAL_EXPONENT + 0.5) / DECIMAL_EXPONENT

	-- now choose the suffix based on index, and send it off
	local suffix = cashSuffixes[suffixIndex] or ``
	return short .. suffix
end

return numberFormatter
