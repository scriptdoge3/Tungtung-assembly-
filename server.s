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

# --- page bodies, baked straight into the binary -----------------------------
index_body:  .incbin "www/index.txt"
.set index_len, . - index_body

about_body:  .incbin "www/about.txt"
.set about_len, . - about_body

how_body:    .incbin "www/how.txt"
.set how_len, . - how_body

body404:     .incbin "www/404.txt"
.set body404_len, . - body404

body405:
    .ascii "405 Method Not Allowed\n\nThis server only speaks GET.\n"
.set body405_len, . - body405

# -------------------------------------------------------------------- bss ---
.section .bss
reqbuf:
    .skip REQBUF_SIZE
itoa_buf:
    .skip 24

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

    # no route matched -> 404
    lea  r14, [rip + hdr404]
    mov  r15, OFFSET hdr404_len
    lea  rbx, [rip + body404]
    mov  rbp, OFFSET body404_len
    jmp  do_respond

serve_index:
    lea  r14, [rip + hdr200]
    mov  r15, OFFSET hdr200_len
    lea  rbx, [rip + index_body]
    mov  rbp, OFFSET index_len
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
