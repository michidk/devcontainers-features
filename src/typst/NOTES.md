## OS and Arch Support

**For v0.3 and up**, ARM and AMD architectures are supported. Ubuntu and Debian images are tested in CI.

### v0.1 and v0.2

For versions 0.1 and 0.2, only AMD/x86 architecture is supported.

"Older" Ubuntu versions (e.g. 20.04) may not work due to typst's glibc requirements (see [typst/typst#109](https://github.com/typst/typst/issues/109)). For these versions, run `ldd --version` to check the glibc version.
