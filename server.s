# Tungtung Assembly Web Server
#
# A complete HTTP/1.1 server in pure x86-64 assembly for Linux.
# No libc, no frameworks, no HTML/JS/TS/JSON/CSS anywhere — just raw
# syscalls serving plain text.
# It opens a TCP socket, accepts connections, parses the HTTP request
# line by hand, and writes HTTP responses byte by byte.
#
# Build:  ./build.sh        Run:  ./server        Visit:  http://localhost:8080

.intel_syntax noprefix

# ---------------------------------------------------------------- syscalls ---
.set SYS_read,        0
.set SYS_write,       1
.set SYS_close,       3
.set SYS_socket,      41
.set SYS_accept,      43
.set SYS_sendto,      44
.set SYS_bind,        49
.set SYS_listen,      50
.set SYS_setsockopt,  54
.set SYS_exit,        60
.set SYS_time,        201

.set AF_INET,         2
.set SOCK_STREAM,     1
.set SOL_SOCKET,      1
.set SO_REUSEADDR,    2
.set MSG_NOSIGNAL,    0x4000
.set BACKLOG,         16
.set REQBUF_SIZE,     4096

# ------------------------------------------------------------------- data ---
.section .rodata

# struct sockaddr_in { u16 family; u16 port(BE); u32 addr; u8 pad[8]; }
sockaddr:
    .word  AF_INET
    .byte  0x1f, 0x90            # port 8080 in network byte order (0x1F90)
    .long  0                     # INADDR_ANY
    .quad  0

one:
    .long  1

banner:
    .ascii "tungtung-asm-httpd listening on http://0.0.0.0:8080\n"
.set banner_len, . - banner

errmsg:
    .ascii "fatal: socket/bind failed (is port 8080 taken?)\n"
.set errmsg_len, . - errmsg

# --- response header prefixes (Content-Length value is appended at runtime) --
hdr200:
    .ascii "HTTP/1.1 200 OK\r\n"
    .ascii "Server: tungtung-asm\r\n"
    .ascii "Content-Type: text/plain; charset=utf-8\r\n"
    .ascii "Content-Length: "
.set hdr200_len, . - hdr200

hdr404:
    .ascii "HTTP/1.1 404 Not Found\r\n"
    .ascii "Server: tungtung-asm\r\n"
    .ascii "Content-Type: text/plain; charset=utf-8\r\n"
    .ascii "Content-Length: "
.set hdr404_len, . - hdr404

hdr405:
    .ascii "HTTP/1.1 405 Method Not Allowed\r\n"
    .ascii "Server: tungtung-asm\r\n"
    .ascii "Allow: GET\r\n"
    .ascii "Content-Type: text/plain; charset=utf-8\r\n"
    .ascii "Content-Length: "
.set hdr405_len, . - hdr405

hdr_tail:
    .ascii "\r\nConnection: close\r\n\r\n"
.set hdr_tail_len, . - hdr_tail

# --- routes ------------------------------------------------------------------
path_root:   .asciz "/"
path_about:  .asciz "/about"
path_how:    .asciz "/how"
path_stats:  .asciz "/stats"

# --- the entire website, as .ascii string data in .rodata --------------------
index_body:
    .ascii "=============================================================================\n"
    .ascii "\n"
    .ascii "  _____ _   _ _   _  ____ _____ _   _ _   _  ____\n"
    .ascii " |_   _| | | | \\ | |/ ___|_   _| | | | \\ | |/ ___|\n"
    .ascii "   | | | | | |  \\| | |  _  | | | | | |  \\| | |  _\n"
    .ascii "   | | | |_| | |\\  | |_| | | | | |_| | |\\  | |_| |\n"
    .ascii "   |_|  \\___/|_| \\_|\\____| |_|  \\___/|_| \\_|\\____|\n"
    .ascii "\n"
    .ascii "                          A S S E M B L Y\n"
    .ascii "\n"
    .ascii "=============================================================================\n"
    .ascii "\n"
    .ascii " You are looking at a website served over real HTTP by a server written\n"
    .ascii " ENTIRELY in x86-64 assembly.\n"
    .ascii "\n"
    .ascii " There is:\n"
    .ascii "\n"
    .ascii "    [x] no HTML        (this is text/plain, straight from the socket)\n"
    .ascii "    [x] no CSS         (what you see is what there is)\n"
    .ascii "    [x] no JavaScript  (view-source and weep: it's identical)\n"
    .ascii "    [x] no TypeScript\n"
    .ascii "    [x] no JSON\n"
    .ascii "    [x] no HTTP library, no framework, no libc\n"
    .ascii "\n"
    .ascii " Just raw Linux syscalls, hand-parsed requests, hand-written responses.\n"
    .ascii "\n"
    .ascii "-----------------------------------------------------------------------------\n"
    .ascii " NAVIGATION (type it in the address bar, or curl it)\n"
    .ascii "-----------------------------------------------------------------------------\n"
    .ascii "\n"
    .ascii "    /            you are here\n"
    .ascii "    /about       what this project is\n"
    .ascii "    /how         the life of a request, syscall by syscall\n"
    .ascii "    /stats       live numbers, computed at request time\n"
    .ascii "    /anything    a hand-rolled 404 that echoes your path back\n"
    .ascii "\n"
    .ascii "-----------------------------------------------------------------------------\n"
    .ascii " THE ENTIRE STACK\n"
    .ascii "-----------------------------------------------------------------------------\n"
    .ascii "\n"
    .ascii "     your browser (or curl)\n"
    .ascii "           |\n"
    .ascii "           |  TCP :8080\n"
    .ascii "           v\n"
    .ascii "     +------------------+\n"
    .ascii "     |  server  (ELF)   |    a tiny static binary\n"
    .ascii "     |                  |\n"
    .ascii "     |   socket(2)      |\n"
    .ascii "     |   bind(2)        |\n"
    .ascii "     |   listen(2)      |\n"
    .ascii "     |   accept(2)      |\n"
    .ascii "     |   read(2)        |  <- parses \"GET /path HTTP/1.1\" by hand\n"
    .ascii "     |   sendto(2)      |  <- writes status line, headers, body by hand\n"
    .ascii "     |   close(2)       |\n"
    .ascii "     +------------------+\n"
    .ascii "           |\n"
    .ascii "           v\n"
    .ascii "     the Linux kernel. that's it. there is nothing else.\n"
    .ascii "\n"
.set index_len, . - index_body

# dynamic footer for the home page, assembled into bodybuf per request
idx_dyn1:
    .ascii "-----------------------------------------------------------------------------\n"
    .ascii " GENERATED ON THE SPOT, JUST FOR YOU\n"
    .ascii "-----------------------------------------------------------------------------\n"
    .ascii "\n"
    .ascii "    this response was not pre-baked. the numbers below were computed\n"
    .ascii "    in registers the moment your request arrived:\n"
    .ascii "\n"
    .ascii "    you are request number ....... "
.set idx_dyn1_len, . - idx_dyn1
idx_dyn2:
    .ascii "\n    seconds since server boot .... "
.set idx_dyn2_len, . - idx_dyn2
idx_dyn3:
    .ascii "\n"
    .ascii "\n"
    .ascii "    (refresh: the number goes up. no javascript did that.)\n"
    .ascii "\n"
.set idx_dyn3_len, . - idx_dyn3

tail_banner:
    .ascii "=============================================================================\n"
    .ascii "  tungtung-asm-httpd -- zero markup, zero scripts, one hundred percent mov\n"
    .ascii "=============================================================================\n"
.set tail_banner_len, . - tail_banner

about_body:
    .ascii "=============================================================================\n"
    .ascii "  ABOUT                                                  tungtung-asm-httpd\n"
    .ascii "=============================================================================\n"
    .ascii "\n"
    .ascii " Tungtung Assembly is an experiment in radical minimalism: a website with\n"
    .ascii " no runtime dependencies and no markup of any kind.\n"
    .ascii "\n"
    .ascii " WHAT IS NOT HERE\n"
    .ascii " ----------------\n"
    .ascii "   * no HTML       -- pages are text/plain; your browser renders raw bytes\n"
    .ascii "   * no CSS        -- the \"design\" is whitespace and ASCII box art\n"
    .ascii "   * no JavaScript, no TypeScript -- not one byte\n"
    .ascii "   * no JSON       -- the only data format is text itself\n"
    .ascii "   * no HTTP library or framework -- requests are parsed with byte\n"
    .ascii "                      compares, responses assembled with sendto(2)\n"
    .ascii "   * no libc       -- the binary is freestanding; it talks straight\n"
    .ascii "                      to the kernel\n"
    .ascii "\n"
    .ascii " WHAT IS HERE\n"
    .ascii " ------------\n"
    .ascii "   * one assembly source file:  server.s  -- the pages themselves\n"
    .ascii "     live inside it as .ascii string data, so the entire website\n"
    .ascii "     is a single .s file\n"
    .ascii "   * a shell script that runs `as` and `ld`. that is the build system.\n"
    .ascii "\n"
    .ascii " NUMBERS\n"
    .ascii " -------\n"
    .ascii "   +--------------------------+----------------------------+\n"
    .ascii "   | thing                    | count                      |\n"
    .ascii "   +--------------------------+----------------------------+\n"
    .ascii "   | lines of HTML            | 0                          |\n"
    .ascii "   | files that are not .s    | build.sh & deploy configs |\n"
    .ascii "   | lines of JavaScript      | 0                          |\n"
    .ascii "   | lines of CSS             | 0                          |\n"
    .ascii "   | npm dependencies         | 0                          |\n"
    .ascii "   | syscalls used            | 10                         |\n"
    .ascii "   | binary size              | ~17 KB, pages included     |\n"
    .ascii "   +--------------------------+----------------------------+\n"
    .ascii "\n"
    .ascii "-----------------------------------------------------------------------------\n"
    .ascii "  <- back home: /          how it works: /how\n"
    .ascii "=============================================================================\n"
.set about_len, . - about_body

how_body:
    .ascii "=============================================================================\n"
    .ascii "  HOW IT WORKS                                           tungtung-asm-httpd\n"
    .ascii "=============================================================================\n"
    .ascii "\n"
    .ascii " The whole server is one loop of raw Linux syscalls.\n"
    .ascii " Here is the life of a request:\n"
    .ascii "\n"
    .ascii " 1. BOOT\n"
    .ascii " -------\n"
    .ascii "    socket(AF_INET, SOCK_STREAM, 0)          ; get a TCP socket\n"
    .ascii "    setsockopt(fd, SOL_SOCKET, SO_REUSEADDR) ; allow fast restarts\n"
    .ascii "    bind(fd, {AF_INET, port 8080, 0.0.0.0})  ; claim the port\n"
    .ascii "    listen(fd, 16)                           ; start accepting\n"
    .ascii "\n"
    .ascii "    The port lives in the binary as two literal bytes, because the\n"
    .ascii "    kernel wants it in network byte order:\n"
    .ascii "\n"
    .ascii "       sockaddr:\n"
    .ascii "           .word  AF_INET\n"
    .ascii "           .byte  0x1f, 0x90        ; 0x1F90 = 8080, big-endian\n"
    .ascii "           .long  0                 ; INADDR_ANY\n"
    .ascii "\n"
    .ascii " 2. RECEIVE THE HTTP REQUEST\n"
    .ascii " ---------------------------\n"
    .ascii "    accept(2) hands over a client socket, read(2) pulls in the raw\n"
    .ascii "    bytes. The method check is a single 4-byte compare -- the string\n"
    .ascii "    \"GET \" is the little-endian dword 0x20544547:\n"
    .ascii "\n"
    .ascii "       cmp  dword ptr [rsi], 0x20544547   ; \"GET \" ?\n"
    .ascii "       jne  send_405\n"
    .ascii "\n"
    .ascii "    Then a byte-by-byte scan slices the path out of\n"
    .ascii "    \"GET /path HTTP/1.1\" by overwriting the first space with a NUL.\n"
    .ascii "\n"
    .ascii " 3. ROUTE\n"
    .ascii " --------\n"
    .ascii "    The path is compared against \"/\", \"/about\" and \"/how\" with a tiny\n"
    .ascii "    hand-written string compare. Anything else falls through to 404.\n"
    .ascii "\n"
    .ascii " 4. SEND THE HTTP RESPONSE\n"
    .ascii " -------------------------\n"
    .ascii "    The response goes out manually, in four pieces:\n"
    .ascii "\n"
    .ascii "      a) a header prefix ending in \"Content-Length: \"\n"
    .ascii "      b) the body length, converted to decimal digits by a hand-\n"
    .ascii "         written itoa (repeated div 10, digits filled right to left)\n"
    .ascii "      c) \"\\r\\nConnection: close\\r\\n\\r\\n\"\n"
    .ascii "      d) the body itself. the pages are not files at all: they are\n"
    .ascii "         .ascii string data inside server.s, assembled straight\n"
    .ascii "         into the binary's .rodata section. and parts of it are\n"
    .ascii "         generated on the spot, per request: the home page footer,\n"
    .ascii "         all of /stats, and the 404's echo of your path are built\n"
    .ascii "         into a buffer with rep movsb the moment you ask\n"
    .ascii "\n"
    .ascii "    Every piece is pushed through a loop around sendto(2) with\n"
    .ascii "    MSG_NOSIGNAL, so short writes resume and a client that hangs up\n"
    .ascii "    early cannot kill the server with SIGPIPE.\n"
    .ascii "\n"
    .ascii " 5. REPEAT\n"
    .ascii " ---------\n"
    .ascii "       close(client)\n"
    .ascii "       jmp  accept_loop\n"
    .ascii "\n"
    .ascii "    That is the entire request lifecycle. No allocator, no threads,\n"
    .ascii "    no event loop -- the server never even calls mmap or brk.\n"
    .ascii "    All memory is static.\n"
    .ascii "\n"
    .ascii "-----------------------------------------------------------------------------\n"
    .ascii "  <- back home: /          about: /about\n"
    .ascii "=============================================================================\n"
.set how_len, . - how_body

body404:
    .ascii "=============================================================================\n"
    .ascii "\n"
    .ascii "      _  _    ___  _  _\n"
    .ascii "     | || |  / _ \\| || |\n"
    .ascii "     | || |_| | | | || |_\n"
    .ascii "     |__   _| |_| |__   _|      N O T   F O U N D\n"
    .ascii "        |_|  \\___/   |_|\n"
    .ascii "\n"
    .ascii "=============================================================================\n"
    .ascii "\n"
    .ascii " These bytes were compared, one by one, in a register --\n"
    .ascii " and none of the routes matched.\n"
    .ascii "\n"
    .ascii "    route:\n"
    .ascii "        call streq      ; \"/\"      ? no\n"
    .ascii "        call streq      ; \"/about\" ? no\n"
    .ascii "        call streq      ; \"/how\"   ? no\n"
    .ascii "        call streq      ; \"/stats\" ? no\n"
    .ascii "        ; fall through to you, right here\n"
.set body404_len, . - body404

# the 404 echoes the requested path back, appended at request time
b404_path:
    .ascii "\n the path your browser asked for:  "
.set b404_path_len, . - b404_path
b404_tail:
    .ascii "\n\n back to safety: /\n"
    .ascii "=============================================================================\n"
.set b404_tail_len, . - b404_tail

body405:
    .ascii "405 Method Not Allowed\n\nThis server only speaks GET.\n"
.set body405_len, . - body405

# --- /stats: a fully request-time-generated page -----------------------------
st1:
    .ascii "=============================================================================\n"
    .ascii "  STATS                                    generated the moment you asked\n"
    .ascii "=============================================================================\n"
    .ascii "\n"
    .ascii " every number on this page was computed at request time, in registers,\n"
    .ascii " by a freestanding binary with no libc:\n"
    .ascii "\n"
    .ascii "    requests served since boot ....... "
.set st1_len, . - st1
st2:
    .ascii "\n    seconds since boot ............... "
.set st2_len, . - st2
st3:
    .ascii "\n    unix time right now .............. "
.set st3_len, . - st3
st4:
    .ascii "\n"
    .ascii "\n"
    .ascii " the machinery: one inc instruction for the counter, the time(2)\n"
    .ascii " syscall for the clocks, and a hand-written div-by-10 loop to turn\n"
    .ascii " the numbers into these very digits.\n"
    .ascii "\n"
    .ascii "-----------------------------------------------------------------------------\n"
    .ascii "  <- back home: /\n"
    .ascii "=============================================================================\n"
.set st4_len, . - st4

# -------------------------------------------------------------------- bss ---
.section .bss
reqbuf:
    .skip REQBUF_SIZE
itoa_buf:
    .skip 24
bodybuf:                         # dynamic responses are assembled here
    .skip 8192
hits:                            # requests served since boot
    .skip 8
boot_time:                       # unix time at startup
    .skip 8

# ------------------------------------------------------------------- code ---
.section .text
.globl _start
_start:
    # fd = socket(AF_INET, SOCK_STREAM, 0)
    mov  eax, SYS_socket
    mov  edi, AF_INET
    mov  esi, SOCK_STREAM
    xor  edx, edx
    syscall
    test rax, rax
    js   fail
    mov  r12, rax                # r12 = listening socket

    # setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &one, 4)
    mov  eax, SYS_setsockopt
    mov  rdi, r12
    mov  esi, SOL_SOCKET
    mov  edx, SO_REUSEADDR
    lea  r10, [rip + one]
    mov  r8d, 4
    syscall

    # bind(fd, &sockaddr, 16)
    mov  eax, SYS_bind
    mov  rdi, r12
    lea  rsi, [rip + sockaddr]
    mov  edx, 16
    syscall
    test rax, rax
    js   fail

    # listen(fd, BACKLOG)
    mov  eax, SYS_listen
    mov  rdi, r12
    mov  esi, BACKLOG
    syscall

    # boot_time = time(NULL)
    call now
    mov  [rip + boot_time], rax

    # write(1, banner, banner_len)
    mov  eax, SYS_write
    mov  edi, 1
    lea  rsi, [rip + banner]
    mov  edx, OFFSET banner_len
    syscall

accept_loop:
    # client = accept(fd, NULL, NULL)
    mov  eax, SYS_accept
    mov  rdi, r12
    xor  esi, esi
    xor  edx, edx
    syscall
    test rax, rax
    js   accept_loop
    mov  r13, rax                # r13 = client socket

    # n = read(client, reqbuf, REQBUF_SIZE - 1)
    xor  eax, eax                # SYS_read
    mov  rdi, r13
    lea  rsi, [rip + reqbuf]
    mov  edx, REQBUF_SIZE - 1
    syscall
    test rax, rax
    jle  close_client
    mov  byte ptr [rsi + rax], 0 # NUL-terminate the raw request
    inc  qword ptr [rip + hits]

    # request must start with "GET "
    cmp  dword ptr [rsi], 0x20544547
    jne  send_405

    # cut the path out of "GET /path HTTP/1.1": terminate at space/CR/LF
    lea  rbx, [rsi + 4]          # rbx = start of path
    mov  rdi, rbx
find_path_end:
    mov  cl, [rdi]
    test cl, cl
    jz   route
    cmp  cl, ' '
    je   cut_path
    cmp  cl, 13                  # '\r'
    je   cut_path
    cmp  cl, 10                  # '\n'
    je   cut_path
    inc  rdi
    jmp  find_path_end
cut_path:
    mov  byte ptr [rdi], 0

route:
    mov  rdi, rbx
    lea  rsi, [rip + path_root]
    call streq
    test al, al
    jnz  serve_index

    mov  rdi, rbx
    lea  rsi, [rip + path_about]
    call streq
    test al, al
    jnz  serve_about

    mov  rdi, rbx
    lea  rsi, [rip + path_how]
    call streq
    test al, al
    jnz  serve_how

    mov  rdi, rbx
    lea  rsi, [rip + path_stats]
    call streq
    test al, al
    jnz  serve_stats

    # no route matched -> 404, generated on the spot: echo the path back.
    # rbx still points at the NUL-terminated path inside reqbuf.
    lea  rdi, [rip + bodybuf]
    lea  rsi, [rip + body404]
    mov  rdx, OFFSET body404_len
    call append
    lea  rsi, [rip + b404_path]
    mov  rdx, OFFSET b404_path_len
    call append
    mov  rsi, rbx                # strlen(path)
    xor  edx, edx
1:  cmp  byte ptr [rsi + rdx], 0
    je   2f
    inc  rdx
    jmp  1b
2:  call append                  # copy the path itself into the page
    lea  rsi, [rip + b404_tail]
    mov  rdx, OFFSET b404_tail_len
    call append
    lea  r14, [rip + hdr404]
    mov  r15, OFFSET hdr404_len
    jmp  finish_dynamic

serve_index:
    # home page = static art + a footer computed at request time
    lea  rdi, [rip + bodybuf]
    lea  rsi, [rip + index_body]
    mov  rdx, OFFSET index_len
    call append
    lea  rsi, [rip + idx_dyn1]
    mov  rdx, OFFSET idx_dyn1_len
    call append
    mov  rax, [rip + hits]
    call append_num
    lea  rsi, [rip + idx_dyn2]
    mov  rdx, OFFSET idx_dyn2_len
    call append
    push rdi
    call now
    pop  rdi
    sub  rax, [rip + boot_time]
    call append_num
    lea  rsi, [rip + idx_dyn3]
    mov  rdx, OFFSET idx_dyn3_len
    call append
    lea  rsi, [rip + tail_banner]
    mov  rdx, OFFSET tail_banner_len
    call append
    lea  r14, [rip + hdr200]
    mov  r15, OFFSET hdr200_len
    jmp  finish_dynamic

serve_stats:
    # every number on this page is computed right now
    lea  rdi, [rip + bodybuf]
    lea  rsi, [rip + st1]
    mov  rdx, OFFSET st1_len
    call append
    mov  rax, [rip + hits]
    call append_num
    lea  rsi, [rip + st2]
    mov  rdx, OFFSET st2_len
    call append
    push rdi
    call now
    pop  rdi
    mov  r8, rax                 # r8 = current unix time
    sub  rax, [rip + boot_time]
    call append_num
    lea  rsi, [rip + st3]
    mov  rdx, OFFSET st3_len
    call append
    mov  rax, r8
    call append_num
    lea  rsi, [rip + st4]
    mov  rdx, OFFSET st4_len
    call append
    lea  r14, [rip + hdr200]
    mov  r15, OFFSET hdr200_len

finish_dynamic:
    lea  rbx, [rip + bodybuf]    # body = [bodybuf, rdi)
    mov  rbp, rdi
    sub  rbp, rbx
    jmp  do_respond

serve_about:
    lea  r14, [rip + hdr200]
    mov  r15, OFFSET hdr200_len
    lea  rbx, [rip + about_body]
    mov  rbp, OFFSET about_len
    jmp  do_respond

serve_how:
    lea  r14, [rip + hdr200]
    mov  r15, OFFSET hdr200_len
    lea  rbx, [rip + how_body]
    mov  rbp, OFFSET how_len
    jmp  do_respond

send_405:
    lea  r14, [rip + hdr405]
    mov  r15, OFFSET hdr405_len
    lea  rbx, [rip + body405]
    mov  rbp, OFFSET body405_len

do_respond:
    call respond

close_client:
    mov  eax, SYS_close
    mov  rdi, r13
    syscall
    jmp  accept_loop

fail:
    mov  eax, SYS_write
    mov  edi, 2
    lea  rsi, [rip + errmsg]
    mov  edx, OFFSET errmsg_len
    syscall
    mov  eax, SYS_exit
    mov  edi, 1
    syscall

# ---------------------------------------------------------------- respond ---
# in: r13 = client fd, r14/r15 = header ptr/len, rbx/rbp = body ptr/len
# sends: header prefix + decimal Content-Length + header tail + body
respond:
    mov  rdi, r13
    mov  rsi, r14
    mov  rdx, r15
    call send_all

    mov  rax, rbp                # format body length as decimal
    call itoa
    mov  rdi, r13
    call send_all                # rsi/rdx were set by itoa

    mov  rdi, r13
    lea  rsi, [rip + hdr_tail]
    mov  rdx, OFFSET hdr_tail_len
    call send_all

    mov  rdi, r13
    mov  rsi, rbx
    mov  rdx, rbp
    call send_all
    ret

# --------------------------------------------------------------- send_all ---
# in: rdi = fd, rsi = buf, rdx = len
# loops sendto(fd, buf, len, MSG_NOSIGNAL) until everything is written,
# so a closed peer gives us -EPIPE instead of a fatal SIGPIPE.
send_all:
1:  test rdx, rdx
    jle  2f
    mov  eax, SYS_sendto
    mov  r10d, MSG_NOSIGNAL
    xor  r8d, r8d
    xor  r9d, r9d
    syscall
    test rax, rax
    jle  2f                      # error or zero -> give up on this client
    add  rsi, rax
    sub  rdx, rax
    jmp  1b
2:  ret

# ----------------------------------------------------------------- append ---
# in:  rdi = dest cursor, rsi = src, rdx = len
# out: rdi advanced past the copied bytes (rsi advances too)
append:
    mov  rcx, rdx
    rep movsb
    ret

# ------------------------------------------------------------- append_num ---
# in:  rdi = dest cursor, rax = unsigned value
# out: rdi advanced past the decimal digits
append_num:
    push rdi
    call itoa                    # rsi = digits, rdx = count
    pop  rdi
    mov  rcx, rdx
    rep movsb
    ret

# -------------------------------------------------------------------- now ---
# out: rax = unix time in seconds
now:
    mov  eax, SYS_time
    xor  edi, edi
    syscall
    ret

# ------------------------------------------------------------------- itoa ---
# in:  rax = unsigned value
# out: rsi = pointer to first digit, rdx = digit count (in itoa_buf)
itoa:
    lea  rdi, [rip + itoa_buf + 23]
    mov  rcx, 10
1:  xor  edx, edx
    div  rcx                     # rax = rax/10, rdx = digit
    add  dl, '0'
    dec  rdi
    mov  [rdi], dl
    test rax, rax
    jnz  1b
    mov  rsi, rdi
    lea  rdx, [rip + itoa_buf + 23]
    sub  rdx, rdi
    ret

# ------------------------------------------------------------------ streq ---
# in:  rdi, rsi = NUL-terminated strings
# out: al = 1 if equal, 0 otherwise
streq:
1:  mov  cl, [rdi]
    mov  dl, [rsi]
    cmp  cl, dl
    jne  2f
    test cl, cl
    jz   3f
    inc  rdi
    inc  rsi
    jmp  1b
2:  xor  eax, eax
    ret
3:  mov  al, 1
    ret
