
INSTALL:
$ luarocks --from=http://data.neuflow.org/lua/rocks install inline

USE:
$ lua
> require 'inline'
> f = inline.load [[
    prinf("Hello, from C!\n");
]]
> f()
Hello, from C!
>

NOTES:
the package depends on external packages: 'sys',
which are automatically installed by Luarocks.
