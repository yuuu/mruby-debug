# Changelog

## [0.2.0] - 2026-11-17

### Added

- Colored output for `mrdbg` and the local `(mrdbg)` prompt: stop banners,
  the prompt, errors, `bt` frame numbers, and `list` with Ruby syntax
  highlighting. `--color auto|always|never` (default `auto`, TTY only),
  `MRDEBUG_COLOR=always|never`, and `NO_COLOR`. Colors are added on the
  host only, so pipes, logs and the DAP bridge see plain text. (#36)
- The on-device console (`console/` gem) is colored by default.
  `MRDEBUG_COLOR=never`, `NO_COLOR` or `TERM=dumb` turns it off (on R2P2:
  `mrdebug_color: never` under `env:` in `/etc/config.yml`). (#36, #42)
- VS Code can start the DAP bridge from `launch.json` alone: point
  vscode-rdbg's `rdbgPath` at `mrdbg` and use a `launch` request. No
  `tasks.json` or `preLaunchTask` is needed. The manual `mrdbg --dap-port`
  + `attach` setup still works. (#38)
- `MRDEBUG_HOST` sets the device host for `mrdbg` (default `127.0.0.1`).
  Every value flag also accepts `--flag=value`. (#38)
- The launch bridge listens on a Unix domain socket when `launch.json` has
  no `debugPort` (in `XDG_RUNTIME_DIR`, else `TMPDIR`, else `/tmp`).
  `debugPort` can also be a socket path or `host:port`. (#45)

### Changed

- An empty line at the `(mrdbg)` prompt shows the prompt again. It used to
  run `continue`, so a stray Enter resumed the program. (#37)
- `mrdbg` exits nonzero with `mrdbg: unknown argument: X` and the usage
  text for an unrecognized argument. Unknown flags used to be ignored. (#44)
- `mrdbg` with no `--port`/`--sock-path` always connects to a device
  (`MRDEBUG_SOCK`, else `MRDEBUG_HOST`:`MRDEBUG_PORT`, default 4711), even
  with other flags such as `--color`. (#44)
- `MRDebug::VERSION` is now kept in step with the release tag. v0.1.0
  still reported `0.0.1`.

### Removed

- The interim demo mode (`mrdbg FILE:LINE`) and `RemoteSession`. Use a
  real device or `binding.debugger` with `MRDEBUG_PORT`/`MRDEBUG_SOCK`
  instead. (#44)

### Fixed

- The DAP bridge no longer dies of SIGPIPE when VS Code closes the
  connection right after `disconnect`, which left a stale socket file
  behind. (#45)
- `--serial DEV` consumes its value. (#44)
- Internal cleanups with no behavior change: shared protocol strings, a
  `Breakpoint` mixin, and deduplicated helpers in `hook.c`/`frame.c`.
  `OwnSource::FILES` lists every Ruby source again, so the debugger no
  longer stops inside its own CLI/transport code. (#40-#43)

### Compatibility

- mruby: master from 2026-09-06 on. Tested with 2a4167e (2026-09-24, the
  CI pin) and 81fd905 (2026-11-17). mruby 4.0.0 does not build, and
  4.1.0-rc/rc2 lose the SIGPIPE guard for socket clients.
- PicoRuby (`PICORB_VM_MRUBY`): tested with 65b7ae6 (the CI pin) and
  e81c48e (2026-11-14) on the POSIX host build.

## [0.1.0] - 2026-09-27

First release of `mrdebug`, rewritten from `picoruby-debug` to run on a
plain mruby checkout as well as PicoRuby (POSIX and R2P2-ESP32).

- `binding.debugger` (also `binding.b` / `binding.break`) with a
  `(mrdbg)` prompt.
- Line, method (`Foo#bar`, `Foo.bar`, `bar`) and conditional breakpoints,
  and watchpoints.
- `step`, `next`, `finish`, `continue`, `bt`, `frame`/`up`/`down`, `list`,
  `cat`, `p`, `help`.
- A TCP/Unix socket console (`mrdbg`) and a DAP bridge for VS Code
  (vscode-rdbg).
- An on-device console gem (`console/`) for R2P2-ESP32.

[0.2.0]: https://github.com/yuuu/mruby-debug/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/yuuu/mruby-debug/releases/tag/v0.1.0
