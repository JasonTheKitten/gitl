## gitl

Welcome to gitl, a git-based VCS designed for a variety of Lua environments!

This project utilizes [Mpeterv's SHA-1](https://github.com/mpeterv/sha1) and [Alex Kloss's Base64](http://lua-users.org/wiki/BaseSixtyFour).

If running on PUC Lua, you will also need to install [LuaFileSystem](https://github.com/lunarmodules/luafilesystem) and [Lua-HTTP](https://github.com/daurnimator/lua-http).

The installation method depends on what environment you are in.

### ComputerCraft

It is recommended, but not required, that you increase the disk space in CC configs.

```
wget run https://raw.githubusercontent.com/JasonTheKitten/gitl/refs/heads/main/misc/gitgitl.lua
reboot
```

### OpenComputers

WARNING: OpenComputers support is highly experimental.
There will be many bugs.

While the highest-tier disk has enough space for gitl,
using two of the highest-tier Memory is not enough, as
gitl is quite memory intense. You will need to increase
memory amounts in the OC configs.

```
wget https://raw.githubusercontent.com/JasonTheKitten/gitl/refs/heads/main/misc/gitgitl.lua
gitgitl.lua
rm gitgitl.lua
reboot
```

### PUC Lua or LuaJIT on Linux

As mentioned in the intro, you will need to install additional
modules via LuaRocks. Make sure to target your Lua installation.

```bash
wget https://raw.githubusercontent.com/JasonTheKitten/gitl/refs/heads/main/misc/gitgitl.lua
lua gitgitl.lua
rm gitgitl.lua
reboot
```

If you are on PUC Lua, you also need to create a symlink
from `/bin/luajit` to `/bin/lua`. This is left as an
exercise for the reader.

### Using gitl

To start, run `gitl -h` just to make sure you can actually
run gitl successfully.
After that, run

```bash
gitl config --global set user.name "Your Name"
gitl config --global set user.email "myemail@example.com"
```

An example project workflow might look like:

```bash
gitl clone https://github.com/jasonthekitten/gitl --depth 10
edit somefile.txt
gitl add .
gitl commit -m "Change a file"
gitl push origin main
```
