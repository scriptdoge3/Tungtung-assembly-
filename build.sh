#!/bin/sh
# Build the Tungtung Assembly web server.
# Needs only binutils (as + ld) — no compiler, no libraries.
set -e
cd "$(dirname "$0")"

as --64 -o server.o server.s
ld -o server server.o
rm -f server.o

echo "built: ./server ($(wc -c < server) bytes)"
echo "run it, then open http://localhost:8080"
