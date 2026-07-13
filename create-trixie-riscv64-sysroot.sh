#!/bin/sh

# Based on https://muxup.com/2024q4/rootless-cross-architecture-debootstrap

TGT=riscv64-debian-trixie-sysroot

# Uses <https://github.com/muxup/medley/blob/main/rootless-debootstrap-wrapper>
~/rootless-debootstrap-wrapper \
  --arch=riscv64 \
  --suite=trixie \
  --mirror=https://deb.debian.org/debian \
  --cache-dir="$HOME/debcache" \
  --target-dir=$TGT \
  --include=build-essential,symlinks,zlib1g-dev,libxml2-dev

"$TGT/_enter" symlinks -cr .
ln -s usr/include "$TGT/include"

tar -C "$TGT" --zstd -cf "$TGT.tar.zst" .
