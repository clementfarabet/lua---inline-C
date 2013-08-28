DEPENDENCIES:
Torch7 (www.torch.ch)

INSTALL:
$ torch-rocks install inline-c

USE:
$ torch
> require 'inline'
> f = inline.load [[
    prinf("Hello, from C!\n");
]]
> f()
Hello, from C!
>
