DEPENDENCIES:
Torch7 (www.torch.ch)

INSTALL:
$ torch-pkg install inline

USE:
$ torch
> require 'inline'
> f = inline.load [[
    prinf("Hello, from C!\n");
]]
> f()
Hello, from C!
>
