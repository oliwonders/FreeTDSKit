# FreeTDS patches

`Support/buildandlinkfreetds.sh` applies every `freetds-*.patch` here, in name
order, to the FreeTDS source before building it. A patch that no longer applies
stops the build, so a FreeTDS upgrade can't silently drop one.

## freetds-tls-verification.patch

Makes per-connection TLS certificate verification possible and correct. It
changes four things:

- **`dbsetltlsverify(login, cafile, certificate_host_name)`** (`dblib.c`,
  `sybdb.h`): a DB-Library entry point for the CA file and the expected
  certificate name. Upstream offers no way to set either except `freetds.conf`,
  which a sandboxed app can't use and which applies to every connection.
  `dbsetlname` isn't used because it caps values at 128 characters, shorter than
  a sandbox container path.
- **`tds_config_login` copies `cafile` and `certificate_host_name`**
  (`config.c`): upstream never copies them from the login to the connection, so
  values set on a login were ignored.
- **Wildcard certificate names match** (`tls.c`): `check_name_match` called
  `check_wildcard(pattern, host)`, but the function takes `(host, pattern)`, as
  its own self-test shows. Wildcard certificates, such as Azure SQL's
  `*.database.windows.net`, therefore never matched. Still present in upstream
  master as of October 2026; worth reporting upstream.

### When upgrading FreeTDS

1. Bump `FREETDS_VERSION` and run the build script. If a hunk fails, re-make
   the change by hand in the new source and regenerate the patch with
   `diff -ru a/ b/`.
2. Check whether upstream has fixed the wildcard order; drop that hunk if so.
3. Run the TLS checks against a server with a public certificate:

       FREETDSKIT_TLS_TEST_HOST=yourserver.database.windows.net swift test --filter TLSVerification
