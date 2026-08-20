# Tungtung Assembly

A website with **zero** runtime dependencies: no HTTP library, no JSON, no
JavaScript, no TypeScript, no CSS. The web server is written entirely in
**pure x86-64 assembly** for Linux — it talks to the kernel directly through
raw syscalls, parses HTTP requests by hand, and writes HTTP responses byte
by byte. There is no libc; the binary is freestanding and static.

## Files

| File | What it is |
|---|---|
| `server.s` | The entire server: sockets, HTTP parsing, routing, responses |
| `www/*.html` | The pages (pure HTML), baked into the binary via `.incbin` |
| `build.sh` | Runs `as` + `ld`. That's the whole build system |

## Build and run

Requires only GNU binutils (`as` and `ld`) on x86-64 Linux:

```sh
./build.sh
./server
```

Then open <http://localhost:8080>. Routes: `/`, `/about`, `/how`, plus a
hand-rolled 404 for everything else and a 405 for non-GET methods.

## How it works

1. `socket(2)` / `setsockopt(2)` / `bind(2)` / `listen(2)` set up TCP on
   port 8080 (the port is two literal big-endian bytes, `0x1f 0x90`).
2. `accept(2)` + `read(2)` pull in the raw request. The method check is a
   single 4-byte compare: `"GET "` is the little-endian dword `0x20544547`.
3. A byte scan slices the path out of `GET /path HTTP/1.1`, and a
   hand-written string compare routes it to a page.
4. The response is sent manually: status line + headers, a `Content-Length`
   value produced by a hand-written `itoa` (repeated `div 10`), then the
   HTML body — all through a `sendto(2)` loop with `MSG_NOSIGNAL` so short
   writes resume and dead clients can't SIGPIPE the server.
5. `close(2)`, jump back to `accept`, forever.

Ten syscalls total. No allocator, no threads, no event-loop library —
all memory is static and the whole thing is a few hundred lines of assembly.
