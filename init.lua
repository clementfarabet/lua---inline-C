----------------------------------------------------------------------
--
-- Copyright (c) 2011 Clement Farabet, Marco Scoffier
-- 
-- Permission is hereby granted, free of charge, to any person obtaining
-- a copy of this software and associated documentation files (the
-- "Software"), to deal in the Software without restriction, including
-- without limitation the rights to use, copy, modify, merge, publish,
-- distribute, sublicense, and/or sell copies of the Software, and to
-- permit persons to whom the Software is furnished to do so, subject to
-- the following conditions:
-- 
-- The above copyright notice and this permission notice shall be
-- included in all copies or substantial portions of the Software.
-- 
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
-- EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
-- MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
-- NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
-- LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
-- OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
-- WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
-- 
----------------------------------------------------------------------
-- description:
--     inline - a package to dynamically build and run C from
--              within Lua.
--
-- history: 
--     July 26, 2011, 8:18PM  - path bug - Clement Farabet
--     March 27, 2011, 9:58PM - creation - Clement Farabet
----------------------------------------------------------------------

require 'os'
require 'io'
require 'sys'
require 'paths'

local _G = _G
local print = print
local error = error
local require = require
local sys = sys
local paths = paths
local os = os
local io = io
local pairs = pairs
local ipairs = ipairs
local debug = debug
local select = select
local string = string
local package = package
local pcall = pcall
module('inline')

----------------------------------------------------------------------
-- Internals
----------------------------------------------------------------------
verbose = false
loaded = {}

----------------------------------------------------------------------
-- Basic Templates
----------------------------------------------------------------------
_template_c_ = [[

static int #FUNCNAME#_l (lua_State *L) {
%s
  return 0;
}

static const struct luaL_reg #FUNCNAME# [] = {
  {"#FUNCNAME#", #FUNCNAME#_l},
  {NULL, NULL}
};

int luaopen_lib#FUNCNAME# (lua_State *L) {
   luaL_openlib(L, "lib#FUNCNAME#", #FUNCNAME#, 0);
   return 1; 
}
]]
_template_c_default_ = _template_c_

----------------------------------------------------------------------
-- File/Line
----------------------------------------------------------------------
get_env = function(exec)
   local dbg = debug.getinfo(3 + (exec or 0))
   local source_path = dbg.source:gsub('@','')
   local source_line = dbg.currentline
   return source_path,source_line
end

----------------------------------------------------------------------
-- Make/Paths
----------------------------------------------------------------------
-- commands
_mkdir_ = 'mkdir -p '
_rmdir_ = 'rm -r '
_make_c_ = 'gcc '
_make_flags_ = ''

-- paths
local function quote(string)
   return "'" .. string:gsub("'","'\\''") .. "'"
end
_make_path_ = paths.concat(os.getenv('HOME'), '.torch', 'inline')
_make_path_q = quote(_make_path_)
_make_includepath_ = ''
_make_libpath_ = '' 
_make_libs_ = ''
_headers_c_ = ''
_headers_local_c_ = ''

----------------------------------------------------------------------
-- Headers
----------------------------------------------------------------------
current_includepaths = {}
function includepaths (...)
   current_path = get_env()
   for i = 1,select('#',...) do
      local path = select(i,...)
      if not current_includepaths[path] then
         _make_includepath_ = _make_includepath_ .. ' -I' .. path
      end
      current_includepaths[path] = true
   end
end

function default_includepaths ()
   _make_includepath_ = ''
   current_includepaths = {}
   includepaths(paths.install_include,'/usr/local/include','/usr/include')
   if paths.dirp('/opt/local/include') then
      includepaths('/opt/local/include')
   end
   if paths.dirp('/sw/include') then
      includepaths('/sw/include')
   end
end

current_headers = {}
function headers (...)
   current_path = get_env()
   for i = 1,select('#',...) do
      local header = select(i,...)
      if not current_headers[header] then
         _headers_c_ = '#include <' .. header .. '>\n' .. _headers_c_
      end
      current_headers[header] = true
   end
end
function default_headers()
   current_headers = {}
   _headers_c_ = ''
   headers('stdlib.h','stdio.h','string.h','math.h','TH/TH.h','luaT.h')
end

-- instead of using inline.headers and inline.preamble sometimes it is
-- just easier to put everything into a local.h file.  Including that
-- file here will copy it to the compilation dir and add -I. to the
-- gcc string
current_localheaders = {}
function localheaders (...)
   current_path = get_env()
   includepaths('.')
   for i = 1,select('#',...) do
      local header = select(i,...)
      if not current_localheaders[header] then
         _headers_local_c_ = '#include "' .. header .. '"\n' .. _headers_local_c_
      end
      current_localheaders[header] = true
   end
end

function default_headers_local()
   current_localheaders = {}
   _headers_local_c_ = ''
end

current_libpaths = {}
function libpaths (...)
   current_path = get_env()
   for i = 1,select('#',...) do
      local path = select(i,...)
      if not current_libpaths[path] then
         _make_libpath_ = _make_libpath_ .. ' -L' .. path
      end
      current_libpaths[path] = true
   end
end
function default_libpaths ()
   _make_libpath_ = '' 
   current_libpaths = {}
   libpaths(paths.install_lib,'/usr/local/lib','/usr/lib')
   if paths.dirp('/opt/local/lib') then
      libpaths('/opt/local/lib')
   end
   if paths.dirp('/sw/lib') then
      libpaths('/sw/lib')
   end
end

current_libs = {}
function libs (...)
   current_path = get_env()
   for i = 1,select('#',...) do
      local lib = select(i,...)
      if not current_libs[lib] then
         _make_libs_ = _make_libs_ .. ' -l' .. lib
      end
      current_libs[lib] = true
   end
end
function default_libs()
   _make_libs_ = ''
   current_libs = {}
   libs('torch-lua','luaT','TH')
end

current_flags = {}
function flags (...)
   current_path = get_env()
   for i = 1,select('#',...) do
      local flag = select(i,...)
      if not current_flags[flag] then
         _make_flags_ = _make_flags_ .. flag .. ' '
      end
      current_flags[flag] = true
   end
end
function default_flags()
   _make_flags_ = ' '
   current_flags = {}
   flags('-fpic', '-shared','-O3')
end

----------------------------------------------------------------------
-- preamble
----------------------------------------------------------------------
function preamble (code_preamble)
   current_path = get_env()
   -- reset the template
   _template_c_ = '\n' .. code_preamble ..'\n'.._template_c_
end

function default_preamble ()
   _template_c_ = _template_c_default_
end

function default_all ()
   default_includepaths()
   default_libpaths()
   default_libs()
   default_headers()
   default_headers_local()
   default_preamble()
   default_flags()
end
default_all()

----------------------------------------------------------------------
-- Compiler
----------------------------------------------------------------------
function load (code,exec)
   -- time
   local tt = sys.clock()

   -- get context
   local c = sys.COLORS
   local source_path,source_line = get_env(exec)
   -- flush headers/libs at end of file
   if source_path ~= current_path then
      default_all()
   end
   current_path = source_path
   local iscompiled = false
   if source_path:find('/') ~= 1 then source_path = sys.concat(sys.pwd(),source_path) end
   local upath = source_path:gsub('%.lua','')..'_'..source_line
   local ref = upath
   local shell = false
   local modtime = sys.fstat(source_path)

   -- lib/src unique names
   if not paths.filep(source_path) then -- this call is from the lua shell
      ref = 'fromshell'
      shell = true
   end
   local funcname = paths.basename(upath)
   local filename = upath .. '.c'
   local libname = paths.concat(paths.dirname(upath), 'lib' .. paths.basename(upath) .. '.so')

   -- check existence of library
   local buildme = true
   if not shell then
      -- has file+line already been loaded ?
      local lib = loaded[ref]
      if lib and (modtime == lib.modtime) then
         -- file hasn't changed, just return local lib
         if verbose then
            print(c.green .. 'reusing preloaded code (originally compiled from '
                  .. source_path .. ' @ line ' .. source_line .. ')'
                  .. ' [in ' .. (sys.clock() - tt) .. ' seconds]' .. c.none)
         end
         return lib.f
      end
      -- or else, has file+line been built in a previous life ?
      local libmodtime = sys.fstat(_make_path_..libname)
      if libmodtime and libmodtime >= modtime then
         -- library was previously built, just reload it !
         if verbose then
            print(c.magenta .. 'reloading library (originally compiled from' 
                  .. source_path .. ' @ line ' .. source_line .. ')' .. c.none)
         end
         buildme = false
      end
   end

   -- if not found, build it
   if buildme then
      if verbose then
         print(c.red .. 'compiling inline code from ' .. source_path .. ' @ line ' .. source_line .. c.none)
      end

      -- parse given code
      local parsed = _headers_c_ .. _headers_local_c_ .. 
	 _template_c_:gsub('#FUNCNAME#',funcname)
      parsed = parsed:format(code)
     
      local compile_dir = _make_path_..paths.dirname(filename)
      local compile_dir_q = quote(compile_dir)
      -- write file to disk
      sys.execute(_mkdir_ .. compile_dir_q)
      local f = io.open(_make_path_..filename, 'w')
      f:write(parsed)
      f:close()
      
      -- copy any local headers to the compilation dir
      for vlh in  pairs(current_localheaders) do 
         sys.execute('cp '..quote(sys.dirname(filename)..'/'..vlh)..' '..
		   compile_dir_q)
      end      	 

      local gcc_str = _make_c_ .. _make_flags_ .. 
	 '-o ' .. paths.basename(libname) .. _make_includepath_  ..
         _make_libpath_ .. _make_libs_ ..
         ' ' .. paths.basename(filename)

      if verbose then
	 print(c.blue .. compile_dir.. c.none)
         print(c.blue .. gcc_str .. c.none)
      end
      -- compile it
      local msgs = sys.execute('cd '..compile_dir_q..'; '.. gcc_str)
      if string.match(msgs,'error') then
         -- cleanup
         sys.execute(_rmdir_ .. quote(_make_path_..filename))
         print(c.blue)
         local debug = ''
         local itr = 1
         local tmp = parsed:gsub('\n','\n: ')
         for line in tmp:gmatch("[^\r\n]+") do 
            if itr == 1 then line = ': ' .. line end
            debug = debug .. itr .. line .. '\n'
            itr = itr + 1
         end
         io.write(debug)
         print(c.red .. 'from GCC:')
         print(msgs .. c.none)
         error('<inline.load> could not compile given code')
      else
         if msgs ~= '' then print(msgs .. c.none) end
      end
   end

   -- load shared lib
   local saved_cpath = package.cpath
   package.cpath = _make_path_..paths.dirname(libname)..'/?.so'
   local loadedlib
   local ok,msg = pcall(function()
                              loadedlib = require(paths.basename(libname):gsub('%.so$',''))
                           end)
   package.cpath = saved_cpath
   if not ok then
      local faulty_lib = paths.concat(_make_path_..paths.dirname(libname), paths.basename(libname))
      sys.execute('rm ' .. quote(faulty_lib))
      print(c.Red..'<inline.load> corrupted library [trying to clean it up, please try again]'..c.none)
      error()
   end

   -- register function for future use
   if not shell then
      loaded[ref] = {modtime=modtime, f=loadedlib[funcname]}
   end

   -- time
   if verbose then
      print(c.green .. '[in ' .. (sys.clock() - tt) .. ' seconds]' .. c.none)
   end

   -- return function
   return loadedlib[funcname]
end

----------------------------------------------------------------------
-- Executer
----------------------------------------------------------------------
function exec (code, ...)
   local func = load(code,1)
   return func(...)
end

----------------------------------------------------------------------
-- Flush all cached libraries
----------------------------------------------------------------------
function flush ()
   -- complete cleanup
   sys.execute(_rmdir_ .. _make_path_q)
end

----------------------------------------------------------------------
-- Test me
----------------------------------------------------------------------
function testme ()
   compiled = load [[
         printf("Hello World\n");
   ]]
   compiled()
end
