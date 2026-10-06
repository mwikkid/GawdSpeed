# Modifications to Rubber Band Library

No file contents have been changed.

Only the files the library build needs were copied from the upstream tag
listed in `VERSION`: `COPYING`, `README.md`, `CHANGELOG`, `rubberband/`
(public headers), `single/` and `src/` (except `src/ext/`, `src/jni/` and
`src/test/`). The omitted directories hold the command-line tool, plugin
wrappers, language bindings, tests, and bundled third-party code that the
single-file build does not compile on macOS. The complete upstream source
is at the URL and commit in `VERSION`.
