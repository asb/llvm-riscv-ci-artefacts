#!/bin/sh

# Based on https://muxup.com/building-32-bit-risc-v-sysroots-and-images-with-yocto

work_dir=$PWD

if [ ! -d bitbake ]; then
  git clone --branch 2.18 https://git.openembedded.org/bitbake
fi

mkdir -p "$HOME/.cache/yocto/dl" "$HOME/.cache/yocto/sstate"
./bitbake/bin/bitbake-setup settings set default dl-dir "$HOME/.cache/yocto/dl"

if [ ! -d bitbake-builds/poky-wrynose ]; then
  ./bitbake/bin/bitbake-setup init --non-interactive \
    --skip-selection machine \
    ./bitbake/default-registry/configurations/poky-wrynose.conf.json \
    poky \
    distro/poky
  printf 'SSTATE_DIR = "%s"\n' "$HOME/.cache/yocto/sstate" >> bitbake-builds/site.conf
fi

. bitbake-builds/poky-wrynose/build/init-build-env
bitbake-config-build enable-fragment machine/qemuriscv32

if [ ! -d ../layers/meta-rv32-llvm-sysroot ]; then
  bitbake-layers create-layer --add-layer ../layers/meta-rv32-llvm-sysroot
fi

recipe_dir="../layers/meta-rv32-llvm-sysroot/recipes-devtools/rv32-llvm-deps-sysroot"
mkdir -p "$recipe_dir"

cat > "$recipe_dir/rv32-llvm-deps-sysroot.bb" <<'EOF'
SUMMARY = "Dependency-only recipe to export an RV32 sysroot"
LICENSE = "MIT-0"

INHIBIT_DEFAULT_DEPS = "1"
EXCLUDE_FROM_WORLD = "1"
PACKAGE_ARCH = "${MACHINE_ARCH}"

DEPENDS = "virtual/libc libgcc virtual/${MLPREFIX}compilerlibs zlib zstd-native"

inherit deploy nopackages

do_configure[noexec] = "1"
do_compile[noexec] = "1"
do_install[noexec] = "1"
do_populate_sysroot[noexec] = "1"

do_deploy() {
    export_dir="${WORKDIR}/${PN}-export"
    rm -rf "$export_dir"
    mkdir -p "$export_dir"
    cp -a "${RECIPE_SYSROOT}/." "$export_dir/"

    sysroot-relativelinks.py "$export_dir"

    mkdir -p "$export_dir/usr/lib/gcc"
    ln -s ../riscv32-poky-linux "$export_dir/usr/lib/gcc/riscv32-linux-gnu"
    ln -s usr/include "$export_dir/include"

    tar -C "$export_dir" -cf - . | \
      zstd -T0 -f -o "${DEPLOYDIR}/riscv32-yocto-wrynose-sysroot.tar.zst"
}
addtask deploy after do_prepare_recipe_sysroot before do_build
EOF

bitbake rv32-llvm-deps-sysroot || exit 1
cp "$work_dir/bitbake-builds/poky-wrynose/build/tmp/deploy/images/qemuriscv32/riscv32-yocto-wrynose-sysroot.tar.zst" "$work_dir/"
