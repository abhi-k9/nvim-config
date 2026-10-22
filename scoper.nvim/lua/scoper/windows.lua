-- GetLongPathName expands 8.3 aliases without resolving symbolic links.
-- Keep the UTF-16 API boundary here; callers and stored scopes use UTF-8.
local ffi = require("ffi")
ffi.cdef([[
  int __stdcall MultiByteToWideChar(unsigned int, unsigned long,
    const char *, int, unsigned short *, int);
  unsigned long __stdcall GetLongPathNameW(const unsigned short *, unsigned short *, unsigned long);
  int __stdcall WideCharToMultiByte(unsigned int, unsigned long,
    const unsigned short *, int, char *, int, const char *, int *);
]])
local kernel = ffi.load("kernel32")
local M = {}

function M.expand(path)
  local count = kernel.MultiByteToWideChar(65001, 8, path, #path, nil, 0)
  if count <= 0 or count > 32767 then return nil end
  local input = ffi.new("unsigned short[?]", count + 1)
  if kernel.MultiByteToWideChar(65001, 8, path, #path, input, count) ~= count then return nil end
  local size = tonumber(kernel.GetLongPathNameW(input, nil, 0))
  if size <= 0 or size > 32768 then return nil end
  local output = ffi.new("unsigned short[?]", size)
  local length = tonumber(kernel.GetLongPathNameW(input, output, size))
  if length <= 0 or length >= size then return nil end
  local bytes = kernel.WideCharToMultiByte(65001, 0, output, length, nil, 0, nil, nil)
  if bytes <= 0 then return nil end
  local utf8 = ffi.new("char[?]", bytes)
  if kernel.WideCharToMultiByte(65001, 0, output, length, utf8, bytes, nil, nil) ~= bytes then
    return nil
  end
  return ffi.string(utf8, bytes)
end

return M
