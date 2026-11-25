# bxtetris

A falling-block game in Bash for X11. It has a shuffled seven-piece bag, a next-piece preview, a landing guide, and gravity that speeds up every ten cleared rows.

## Run

The game requires Bash 5 or newer and an X11 display with a TrueColor default visual. Run it with your existing `DISPLAY`.

```sh
bash ./bxtetris
```

Host-qualified displays such as `localhost:10.0` use Bash's `/dev/tcp` and work without a module. A bare local display such as `:0` tries the Unix socket first and falls back to loopback TCP. Use `unix/:0` to require a Unix socket. Both transports read the MIT-MAGIC-COOKIE-1 cookie from `XAUTHORITY` or `~/.Xauthority`.

## Unix socket modules

Choose a module that matches your platform and Bash architecture. On macOS, place `x11-unix.dylib` beside `x11.bash`. On the other platforms, run `ln -s MODULE x11-unix.so` in that directory, replacing `MODULE` with the filename from the table.

| Platform | Bash architecture | Module |
| --- | --- | --- |
| Linux (GNU libc) | AMD64 | `x11-unix.so.amd64.linux.gnu` |
| Linux (GNU libc) | AArch64 | `x11-unix.so.aarch64.linux.gnu` |
| FreeBSD 15.1 | AMD64 | `x11-unix.so.amd64-unknown-freebsd15.1` |
| FreeBSD 15.1 | AArch64 | `x11-unix.so.aarch64-unknown-freebsd15.1` |
| illumos or Oracle Solaris | AMD64 | `x11-unix.so.amd64-pc-solaris2.11` |
| Oracle Solaris | 64-bit SPARC V9 | `x11-unix.so.sparcv9-sun-solaris2.11` |
| macOS | AMD64 or ARM64 | `x11-unix.dylib` |

The AMD64 module targets the SunOS 5.11 ABI shared by illumos and Oracle Solaris. Both Solaris-targeted modules use OpenSolaris 2009.06 libraries as the link baseline. Native loading on Oracle Solaris has yet to be tested.

Local Unix displays use paths such as `/tmp/.X11-unix/X0`. XQuartz's launchd socket paths in `DISPLAY` are currently unsupported.

Stock Bash can read and write an open file descriptor, but it cannot connect to a Unix-domain socket. Redirecting to a path such as `/tmp/.X11-unix/X0` attempts a regular file open. The socket requires `socket()` and `connect()`. Bash loads the module as a builtin so those calls run in the Bash process. The builtin returns the connected descriptor and unloads, then Bash handles all X11 traffic.

### Build from source

Set `BASH_HEADERS` to the development header directory for the Bash build that will load the module. It should contain `config.h`, `builtins/common.h`, and the `include` subdirectory.

On ELF platforms, build `x11-unix.so` with a compiler for the target OS and architecture. On illumos or Solaris, add `-lsocket` at the end of the command.

```sh
cc -fPIC -shared -DHAVE_CONFIG_H -DSHELL \
  -I"$BASH_HEADERS" -I"$BASH_HEADERS/builtins" -I"$BASH_HEADERS/include" \
  -o x11-unix.so x11-unix.c
```

#### macOS universal module

Set `BASH_HEADERS_AMD64` and `BASH_HEADERS_ARM64` to the macOS Bash development header directories for Intel and Apple Silicon, respectively. Each slice needs the headers for the Bash build that will load it. Both examples use macOS 11.0 as the deployment target.

**Cross-compiling with upstream Clang.** On a non-Mac host, set `MACOS_SDK` to the path of a macOS SDK with both architectures. With LLVM Clang, LLD, and `llvm-lipo` installed, build the two slices and merge them.

```sh
clang --target=x86_64-apple-macos11.0 -isysroot "$MACOS_SDK" -fuse-ld=lld \
  -dynamiclib -Wl,-undefined,dynamic_lookup -DHAVE_CONFIG_H -DSHELL \
  -I"$BASH_HEADERS_AMD64" -I"$BASH_HEADERS_AMD64/builtins" -I"$BASH_HEADERS_AMD64/include" \
  -o x11-unix.x86_64.dylib x11-unix.c

clang --target=arm64-apple-macos11.0 -isysroot "$MACOS_SDK" -fuse-ld=lld \
  -dynamiclib -Wl,-undefined,dynamic_lookup -DHAVE_CONFIG_H -DSHELL \
  -I"$BASH_HEADERS_ARM64" -I"$BASH_HEADERS_ARM64/builtins" -I"$BASH_HEADERS_ARM64/include" \
  -o x11-unix.arm64.dylib x11-unix.c

llvm-lipo -create x11-unix.x86_64.dylib x11-unix.arm64.dylib -output x11-unix.dylib
llvm-lipo -archs x11-unix.dylib
```

**Building with Apple Clang.** On a Mac with Xcode or its Command Line Tools, pass both `-arch` flags in one invocation. The compiler driver builds and merges the slices.

```sh
xcrun --sdk macosx clang -arch x86_64 -arch arm64 -mmacosx-version-min=11.0 \
  -isysroot "$(xcrun --sdk macosx --show-sdk-path)" \
  -dynamiclib -Wl,-undefined,dynamic_lookup -DHAVE_CONFIG_H -DSHELL \
  -Xarch_x86_64 -I"$BASH_HEADERS_AMD64" \
  -Xarch_x86_64 -I"$BASH_HEADERS_AMD64/builtins" \
  -Xarch_x86_64 -I"$BASH_HEADERS_AMD64/include" \
  -Xarch_arm64 -I"$BASH_HEADERS_ARM64" \
  -Xarch_arm64 -I"$BASH_HEADERS_ARM64/builtins" \
  -Xarch_arm64 -I"$BASH_HEADERS_ARM64/include" \
  -o x11-unix.dylib x11-unix.c

xcrun lipo -archs x11-unix.dylib
```

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
