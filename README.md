# mrdebug

An interactive debugger for **mruby** (and PicoRuby's mruby VM). Put
`binding.debugger` in a script and it pauses there with a `(mrdbg)` prompt.

## Installation

Add the gem to your mruby `build_config.rb`:

```ruby
conf.gem github: 'yuuu/mruby-debug', branch: 'main'
```

On a PicoRuby device (e.g. R2P2-ESP32), either gem works. The on-device
console gem under `console/` pulls in `mrdebug` itself and adds the
`(mrdbg)` prompt on the device's own console (see [On a device](#on-a-device)):

```ruby
conf.gem github: 'yuuu/mruby-debug', branch: 'main', path: 'console'
```

On R2P2-ESP32, also raise the PicoRuby task stack to at least 32768 bytes
(`PICORB_TASK_STACK_SIZE=32768` in the environment of the ESP-IDF build);
the 8192 default overflows as soon as the debugger stops.

## Usage

### Example

```ruby
def add(a, b)
  a + b
end

x = 1
binding.debugger # or binding.b / binding.break
y = add(x, 2)
puts y
```

```
$ mruby script.rb
Stop: script.rb:6
(mrdbg) n
Stop: script.rb:7
(mrdbg) p y
nil
(mrdbg) break 2
Breakpoint 1 added at script.rb:2
(mrdbg) c
Breakpoint 1: script.rb:2
(mrdbg) p a + b
3
(mrdbg) bt
#0 script.rb:2
#1 script.rb:7
(mrdbg) c
3
```

No setup call is needed: the first `binding.debugger` opens the prompt on
the script's own terminal (piped input such as `printf 'n\nc\n' | mruby
script.rb` also works).

### Commands

| Command | Alias | Description |
| --- | --- | --- |
| `continue` | `c`, empty input | Resume until the next breakpoint |
| `step [<n>]` | `s` | Stop at the next executed line, entering calls |
| `next [<n>]` | `n` | Stop at the next line in the same or a shallower frame |
| `finish` | `fin` | Run until the selected frame returns; stop at the call site in its caller |
| `break [<file>:]<line> [if <expr>]` | `b` | Add a line breakpoint (no argument lists breakpoints) |
| `break <Class>#<method>` / `<Class>.<method>` / `<method>` | `b` | Add a method breakpoint (`#` instance, `.` singleton, bare = any class) |
| `delete [<n>]` | `d` | Delete breakpoint `<n>`, or all with no argument |
| `watch [<expr>]` | | Stop when `<expr>`'s value changes (no argument lists watches) |
| `display <expr>` | | Print `<expr>` at every stop |
| `print <expr>` | `p` | Evaluate `<expr>` in the selected frame |
| `info [locals]` | `i` | Show the selected frame's local variables |
| `list [[<file>:]<line>]` | `l` | Show source around the current line |
| `cat [<file>]` | | Show a whole source file |
| `backtrace` | `bt`, `where` | Show the call stack (`#0` = innermost) |
| `frame [<n>]` | `f` | Select frame `<n>`, or show the selected frame |
| `up [<n>]` / `down [<n>]` | | Move the selected frame toward the caller / back |
| `help [<command>]` | `h` | List commands, or show `<command>`'s usage |

- File names match by suffix: `break foo.rb:8` matches `/path/to/foo.rb`.
- A method breakpoint stops inside a Ruby method, or just before calling a
  C method. `Foo#bar` also matches subclasses and includers, and `Foo` need
  not be defined yet.
- `frame`/`up`/`down` only affect `print`/`info`/`list`; execution always
  resumes from the actual stop.

### Remote connection

Set an environment variable and `binding.debugger` waits for a client
instead of using the local terminal:

```sh
MRDEBUG_PORT=4711 mruby script.rb       # or MRDEBUG_SOCK=/tmp/mrdebug.sock
```

```sh
mrdbg                                    # reads MRDEBUG_PORT / MRDEBUG_SOCK
mrdbg --host 192.168.0.10 --port 4711    # e.g. a board on the network
```

While it waits, the process prints `mrdebug: waiting for a debugger on
port 4711` to stderr. When the client disconnects, the program runs on,
and the next `binding.debugger` it reaches waits for a new client. A
long-running program can be attached to again without restarting it.

### On a device

A device script needs nothing but `binding.debugger`. With no setting, the
firmware's gem decides what happens when it reaches one:

- built with the `console/` gem (`path: 'console'`): the `(mrdbg)` prompt
  opens on the device's own console
- built with `mrdebug` alone: the device listens on TCP port 4711, for
  `mrdbg` or VS Code

To choose otherwise on R2P2, set `mrdebug_port` in `/etc/config.yml` (R2P2
loads its `env:` section into `ENV` at boot). A number makes the device
listen on that TCP port even with the `console/` gem. `console` opens the
on-device prompt, which needs the `console/` gem:

```yaml
env:
  mrdebug_port: 4711      # e.g. to attach VS Code to a console/ build
```

`export MRDEBUG_PORT=4711` in the R2P2 shell does the same for that
session.

### Connecting from VS Code

`mrdbg` can bridge a DAP client to a listening device. Start the bridge:

```sh
mrdbg --host 192.168.0.10 --port 4711 --dap-port 12345
```

Then attach with [vscode-rdbg](https://marketplace.visualstudio.com/items?itemName=KoichiSasada.vscode-rdbg):

```json
{
  "type": "rdbg",
  "request": "attach",
  "name": "Attach to mrdbg",
  "debugPort": "localhost:12345"
}
```

To have VS Code start the bridge itself, run `mrdbg` as a background task
and name it as the attach configuration's `preLaunchTask`. VS Code waits for
the `DAP bridge listening on` line before attaching. If the device can't be
reached, `mrdbg` exits nonzero and the debug session doesn't start. The
bridge exits when the session ends, so each F5 starts a fresh one. Start the
script on the device first, so that it's waiting in `binding.debugger`.

`.vscode/tasks.json`:

```json
{
  "version": "2.0.0",
  "tasks": [
    {
      "label": "mrdbg bridge",
      "type": "process",
      "command": "/path/to/build/host/bin/mrdbg",
      "args": ["--host", "192.168.0.10", "--port", "4711", "--dap-port", "12345"],
      "isBackground": true,
      "problemMatcher": {
        "owner": "mrdbg",
        "pattern": { "regexp": "^never-matches$" },
        "background": {
          "activeBegins": true,
          "beginsPattern": "^Connected to device",
          "endsPattern": "^DAP bridge listening on"
        }
      }
    }
  ]
}
```

`.vscode/launch.json`:

```json
{
  "type": "rdbg",
  "request": "attach",
  "name": "Attach to device",
  "debugPort": "localhost:12345",
  "preLaunchTask": "mrdbg bridge"
}
```

Line breakpoints (with conditions), function breakpoints (`Class#method`,
`Class.method`, `method`), continue, step over/in/out, the call stack, source
view, local variables per frame and evaluation (Debug Console, hover, Watch
panel) work. Values are shown by `inspect` and can't be expanded. Data
breakpoints (`watch`) and pause are not supported yet.

A running device doesn't read from the connection, so breakpoints set while
the program runs take effect only at its next stop (VS Code shows them as
unverified until then). Disconnecting removes every breakpoint and lets the
program run to the end.

## Features

- **Zero configuration** — `binding.debugger` is the only line a script needs.
- **Small C footprint** — only the VM hook and frame walking are in C
  (`src/`); breakpoints, sessions and commands are plain Ruby.
- **No cost until armed** — with no breakpoint set and no step in progress,
  the VM runs as fast as without the gem. Once armed, every executed line
  calls into Ruby (about 1.8µs/line, ~145x on a tight loop).
- **Runs on devices** — works on PicoRuby's mruby VM, including R2P2-ESP32.
- **Remote and DAP** — a TCP/Unix socket console and a VS Code bridge.

Note that the gem sets `MRB_USE_DEBUG_HOOK`, which applies to the whole
build.

## Dependencies

- mruby 4.0.0+, or PicoRuby with `PICORB_VM_MRUBY`
- `mruby-binding`, `mruby-eval`
- Host builds only: `mruby-io`, `mruby-socket`, `mruby-env`
  (`picoruby-socket` / `picoruby-env` on PicoRuby)
- `console/` only: `picoruby-editor`, `picoruby-io-console`

## Roadmap

- `quit`, `catch` (exception breakpoints)
- Pause over DAP
- A serial transport
- PicoRuby's mruby/c VM (not supported: it has no debug hook)
