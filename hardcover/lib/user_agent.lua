local T = require("ffi/util").template
local VERSION = require("hardcover_version")

local UserAgent =
  T("hardcoverapp.koplugin/%1 (https://github.com/billiam/hardcoverapp.koplugin)", table.concat(VERSION, "."))

return UserAgent
