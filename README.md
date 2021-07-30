# Docker OpenXPKI alpine
A builder for OpenXPKI in Alpine, for no particular reason and unlikely to offer any benefit to justify the time and effort. :)

There's a few required modules that can't be installed automatically and need patching.

The build fails some `make test` tests, but so does a Debian build. Either I'm doing something fundementally wrong in both cases or the tests don't all work.

There's issues talking to the database when OpenXPKI is run, it's unclear at this stage if that's a problem with the build or a missing OS component. Could well be both. :) More investigation is required.

There's notes scattered through the Dockerfiles, as well as what's on this page.

**Note:** The images in this branch are for building OpenXPKI and poking at it from the shell, they're not configured to provide a functional OpenXPKI server out of the box.

## Usage
```
./build.sh <build_type>
```
..where `<build_type>` is `alpine` or `debian`.

Then either run the image or create a container and exec into the shell. Along these lines:
```
docker run --rm -ti moonbuggy2000/openxpki:<build_type>-builder <cmd>
```
..where `<cmd>` is `ash` for Alpine, `bash` for Debian, or whatever else you might want.

## Fixes

###	Config::Versioned

#### Use of uninitialized value $ENV{"USER"} in concatenation (.) or string at [...]`
Setting a USER (`export USER=root`) seems to make it go.

###	XML::Parser::Lite
Missing `perldiag.pod` file.

```
RUN mkdir -p /usr/share/perl5/core_perl/pods/ \
	&&	wget -qO- https://raw.githubusercontent.com/Perl/perl5/blead/pod/perldiag.pod > /usr/share/perl5/core_perl/pods/perldiag.pod
```

### Proc::ProcessTable
See: https://github.com/jwbargsten/perl-proc-processtable/pull/29

#### implicit delcaration of canonicalize_file_name() warnings
Use `realpath()` instead.

#### obstack
```
RUN apk add musl-obstack-dev
```

#### Patch
```
diff --git a/Makefile.PL b/Makefile.PL
index 805e448..371ea91 100644
--- a/Makefile.PL
+++ b/Makefile.PL
@@ -17,7 +17,7 @@ my %WriteMakefileArgs = (
     ABSTRACT_FROM    => 'lib/Proc/ProcessTable.pm',
     LICENSE          => 'artistic_2',
     'LDFROM'    => '$(O_FILES)',
-    'LIBS'     => [''],
+    'LIBS'     => ['-lobstack'],
     'OBJECT'    => 'ProcessTable.o OS.o',
     MIN_PERL_VERSION => '5.006',
     CONFIGURE_REQUIRES => {
diff --git a/os/Linux.c b/os/Linux.c
index 987bc62..023a884 100644
--- a/os/Linux.c
+++ b/os/Linux.c
@@ -328,7 +328,11 @@ static bool get_proc_stat(char *pid, char *format_str, struct procstat* prs,
     /* scan in pid, and the command, in linux the command is a max of 15 chars
      * plus a terminating NULL byte; prs->comm will be NULL terminated since
      * that area of memory is all zerored out when prs is allocated */
-    if (sscanf(stat_text, "%d (%15c", &prs->pid, prs->comm) != 2)
+    /* Apparently %15c means 'exactly 15' but a glibc bug allows matching
+     * regardles. musl won't match it.
+     * See: https://www.openwall.com/lists/musl/2013/11/15/5
+     * and: https://sourceware.org/bugzilla/show_bug.cgi?id=12701 */
+    if (sscanf(stat_text, "%d (%c", &prs->pid, prs->comm) != 2)
       /* we might get an empty command name, so check for it:
        * do the open and close parenteses lie next to each other?
        * proceed if yes, finish otherwise
@@ -393,7 +397,8 @@ static void eval_link(char *pid, char *link_rel, enum field field, char **ptr,
      * for the cwd symlink, since on linux the links we care about will never
      * be relative links (cwd, exec)
      * Doing this because readlink works on static buffers */
-    link = canonicalize_file_name(link_file);
+    /* canonicalize_file_name is no good for musl, use realpath instead */
+    link = realpath(link_file, NULL);

     /* we no longer need need the path to the link file */
     obstack_free(mem_pool, link_file);
diff --git a/t/process.t b/t/process.t
index 3bd6853..16a8c07 100644
--- a/t/process.t
+++ b/t/process.t
@@ -84,5 +84,6 @@ else
 {
   # child, fork returned 0
   # child process will be killed soon
-  sleep 10000;
+  # 10,000 seconds is a long time to wait
+  sleep 10;
 }
```

## Building
The container wants some DB ENV set for testing the OpenXPKI build. From this code:
```
	type    => "MariaDB",
	$ENV{OXI_TEST_DB_MYSQL_DBHOST} ? ( host => $ENV{OXI_TEST_DB_MYSQL_DBHOST} ) : (),
	$ENV{OXI_TEST_DB_MYSQL_DBPORT} ? ( port => $ENV{OXI_TEST_DB_MYSQL_DBPORT} ) : (),
	name    => $ENV{OXI_TEST_DB_MYSQL_NAME},
	user    => $ENV{OXI_TEST_DB_MYSQL_USER},
	passwd  => $ENV{OXI_TEST_DB_MYSQL_PASSWORD},
```

This is handled by `entrypoint.sh`, using the same ENV variables on the container. The entrypoint script also patches some tests that have `127.0.0.1` hard coded as the database host.

### Test failures
```
t/25_crypto/11_use_ca.t ........................................ 6/17
#   Failed test 'Create EC key'
#   at t/25_crypto/11_use_ca.t line 113.
# died: OpenXPKI::Exception (I18N_OPENXPKI_TOOLKIT_COMMAND_FAILED; __COMMAND__ => OpenXPKI::Crypto::Backend::OpenSSL::Command::create_params, __ERRVAL__ => I18N_OPENXPKI_CRYPTO_CLI_EXECUTE_FAILED; __EXIT_STATUS__ => 256)
140501916904264:error:08064066:object identifier routines:OBJ_create:oid exists:crypto/objects/obj_dat.c:709:
t/25_crypto/11_use_ca.t ........................................ 17/17 # Looks like you failed 1 test of 17.
```

This one repeats in other tests:
```
t/25_crypto/12_conversion.t .................................... 1/18 140624946785096:error:08064066:object identifier routines:OBJ_create:oid exists:crypto/objects/obj_dat.c:709:
139707648273224:error:08064066:object identifier routines:OBJ_create:oid exists:crypto/objects/obj_dat.c:709:
140669954550600:error:08064066:object identifier routines:OBJ_create:oid exists:crypto/objects/obj_dat.c:709:
140052255533896:error:08064066:object identifier routines:OBJ_create:oid exists:crypto/objects/obj_dat.c:709:
139647013317448:error:08064066:object identifier routines:OBJ_create:oid exists:crypto/objects/obj_dat.c:709:
```

```
t/50_auth/02.t ................................................. 1/18
#   Failed test 'Anonymous'
#   at t/50_auth/02.t line 46.
Got invalid authentication stack; __STACK__ => Password# Looks like your test exited with 255 just after 3.
```

```
t/50_auth/06.t ................................................. 1/31
#   Failed test at t/50_auth/06.t line 26.
t/50_auth/test.sh: No such file or directory
# Looks like your test exited with -1 just after 18.
```

```
t/92_api2_plugins/10_token.t ................................... 1/17
#   Failed test 'get_ca_list - list signing CAs with correct status'
#   at t/92_api2_plugins/10_token.t line 83.
# Comparing $data as a Bag
# Missing: 1 reference
# Extra: 1 reference
140169602362184:error:08064066:object identifier routines:OBJ_create:oid exists:crypto/objects/obj_dat.c:709:
t/92_api2_plugins/10_token.t ................................... 11/17 139779201592136:error:08064066:object identifier routines:OBJ_create:oid exists:crypto/objects/obj_dat.c:709:
140511006583624:error:08064066:object identifier routines:OBJ_create:oid exists:crypto/objects/obj_dat.c:709:
140287252458312:error:08064066:object identifier routines:OBJ_create:oid exists:crypto/objects/obj_dat.c:709:
# Looks like you failed 1 test of 17.
t/92_api2_plugins/10_token.t ................................... Dubious, test returned 1 (wstat 256, 0x100)
Failed 1/17 subtests
t/92_api2_plugins/20_get_openapi_typespec.t .................... ok
t/92_api2_plugins/30_crypto_password_quality.t ................. 1/31
#   Failed test 'invalid password !d.4_SuNset (I18N_OPENXPKI_UI_PASSWORD_QUALITY_CONTAINS_DICT_WORD)'
#   at t/92_api2_plugins/30_crypto_password_quality.t line 49.
# Compared array length of $data
#    got : array with 0 element(s)
# expect : array with 1 element(s)
# []
t/92_api2_plugins/30_crypto_password_quality.t ................. 15/31
#   Failed test 'invalid password tRoublEShooting (I18N_OPENXPKI_UI_PASSWORD_QUALITY_DICT_WORD)'
#   at t/92_api2_plugins/30_crypto_password_quality.t line 49.
# Compared array length of $data
#    got : array with 0 element(s)
# expect : array with 1 element(s)
# []

#   Failed test 'invalid password tr0ubl3shoot1NG (I18N_OPENXPKI_UI_PASSWORD_QUALITY_DICT_WORD)'
#   at t/92_api2_plugins/30_crypto_password_quality.t line 49.
# Compared array length of $data
#    got : array with 0 element(s)
# expect : array with 1 element(s)
# []

#   Failed test 'invalid password gnitoohselbuort (I18N_OPENXPKI_UI_PASSWORD_QUALITY_REVERSED_DICT_WORD)'
#   at t/92_api2_plugins/30_crypto_password_quality.t line 49.
# Compared array length of $data
#    got : array with 0 element(s)
# expect : array with 1 element(s)
# []

#   Failed test 'Reports only errors of lowest complex checks'
#   at t/92_api2_plugins/30_crypto_password_quality.t line 162.
# Compared array length of $data
#    got : array with 3 element(s)
# expect : array with 4 element(s)
# Looks like you failed 5 tests of 31.
t/92_api2_plugins/30_crypto_password_quality.t ................. Dubious, test returned 5 (wstat 1280, 0x500)
```

```
Test Summary Report
-------------------
t/25_crypto/11_use_ca.t                                      (Wstat: 256 Tests: 17 Failed: 1)
  Failed test:  7
  Non-zero exit status: 1
t/50_auth/02.t                                               (Wstat: 65280 Tests: 3 Failed: 1)
  Failed test:  3
  Non-zero exit status: 255
  Parse errors: Bad plan.  You planned 18 tests but ran 3.
t/50_auth/06.t                                               (Wstat: 65280 Tests: 18 Failed: 1)
  Failed test:  1
  Non-zero exit status: 255
  Parse errors: Bad plan.  You planned 31 tests but ran 18.
t/92_api2_plugins/10_token.t                                 (Wstat: 256 Tests: 17 Failed: 1)
  Failed test:  1
  Non-zero exit status: 1
t/92_api2_plugins/30_crypto_password_quality.t               (Wstat: 1280 Tests: 31 Failed: 5)
  Failed tests:  8, 15-17, 25
  Non-zero exit status: 5
Files=92, Tests=2013, 203 wallclock secs ( 0.71 usr  0.29 sys + 172.35 cusr 16.90 csys = 190.25 CPU)
Result: FAIL
Failed 5/92 test programs. 9/2013 subtests failed.
```
