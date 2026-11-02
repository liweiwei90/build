# BR2_GLOBAL_PATCH_DIR

Hashes for the OP-TEE sources pinned to 4.6.0. `BR2_DOWNLOAD_FORCE_CHECK_HASHES=y`
clears Buildroot's `BR_NO_CHECK_HASH_FOR` exemption list (`package/pkg-download.mk`),
so every custom tarball needs a hash here; the in-tree `package/*/*.hash` files only
carry the version Buildroot currently ships.

`optee-examples/custom/` and `optee-test/custom/` each carry a
`0001-cmake-bump-minimum-to-3.5.patch` so the 4.6.0 pins configure
under host-cmake 4.x (CMake 4 dropped compatibility with minima below
3.5; upstream raised these after 4.6.0).
