# bxtetris

A falling-block game in Bash for X11. It has a shuffled seven-piece bag, a next-piece preview, a landing guide, and gravity that speeds up every ten cleared rows.

## Run

For a local Unix-socket display such as `:0`, build the Bash loadable builtin once, then run the game with your existing `DISPLAY`.

```sh
cc -fPIC -shared -DHAVE_CONFIG_H -DSHELL \
  -I/usr/include/bash -I/usr/include/bash/builtins -I/usr/include/bash/include \
  -o x11-unix.so x11-unix.c
./bxtetris
```

Stock Bash can read and write an open file descriptor, but it cannot connect to a Unix-domain socket. Redirecting to a path such as `/tmp/.X11-unix/X0` attempts a regular file open. The socket requires `socket()` and `connect()`. Bash loads `x11-unix.so` as a builtin so those calls run in the Bash process. The builtin returns the connected descriptor and unloads, then Bash handles all X11 traffic.

Building the shared object requires a C compiler and the development headers for your Bash installation. Adjust the three include paths if your headers are installed outside `/usr/include/bash`.

The game requires Bash 5+ and a TrueColor default X11 visual. Host-qualified displays such as `localhost:10.0` use Bash's `/dev/tcp` and work without building the shared object. A bare local display such as `:0` tries the Unix socket first and falls back to loopback TCP. Use `unix/:0` to require a Unix socket. Both transports read the MIT-MAGIC-COOKIE-1 cookie from `XAUTHORITY` or `~/.Xauthority`.

## Controls

| Key | Action |
| --- | --- |
| Left / Right or A / D | Move sideways |
| Down or S | Soft drop |
| Up or X | Rotate clockwise |
| Z | Rotate counterclockwise |
| Space | Hard drop |
| P | Pause or resume |
| R | Restart |
| Esc or Q | Quit |
