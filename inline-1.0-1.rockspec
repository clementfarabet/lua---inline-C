
package = "inline"
version = "1.0-1"

source = {
   url = "inline-1.0-1.tgz"
}

description = {
   summary = "Provides inline C capability",
   detailed = [[
         This package provides a functions to write inline
         C from Lua. It abstracts compilation/paths/loading.
   ]],
   homepage = "",
   license = "MIT/X11" -- or whatever you like
}

dependencies = {
   "lua >= 5.1",
   "sys"
}

build = {
   type = "builtin",
   modules = {
      inline = "inline.lua",
   }
}
