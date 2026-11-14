# FreeTDS patches

`Support/buildandlinkfreetds.sh` applies every `freetds-*.patch` here, in name
order, to the FreeTDS source before building it. A patch that no longer applies
stops the build, so a FreeTDS upgrade can't silently drop one.

## freetds-tls-verification.patch

Makes per-connection TLS certificate verification possible and correct. It
changes two things:

- **`dbsetltlsverify(login, cafile, certificate_host_name)`** (`dblib.c`,
  `sybdb.h`): a DB-Library entry point for the CA file and the expected
  certificate name. Upstream offers no way to set either except `freetds.conf`,
  which a sandboxed app can't use and which applies to every connection.
  `dbsetlname` isn't used because it caps values at 128 characters, shorter than
  a sandbox container path.
- **`tds_config_login` copies `cafile` and `certificate_host_name`**
  (`config.c`): upstream never copies them from the login to the connection, so
  values set on a login were ignored.

It used to fix a third: `check_name_match` (`tls.c`) passed its arguments to
`check_wildcard` in the wrong order, so wildcard certificates such as Azure
SQL's `*.database.windows.net` never matched. FreeTDS 1.5.21 has the fix
upstream, and the hunk was dropped.

### When upgrading FreeTDS

1. Bump `FREETDS_VERSION` and run the build script. If a hunk fails, re-make
   the change by hand in the new source and regenerate the patch with
   `diff -ru a/ b/`.
2. Check whether upstream now copies `cafile` and `certificate_host_name` in
   `tds_config_login`, or offers a per-login way to set them; drop that part
   if so.
3. Run the TLS checks against a server with a public certificate:

       FREETDSKIT_TLS_TEST_HOST=yourserver.database.windows.net swift test --filter TLSVerification
