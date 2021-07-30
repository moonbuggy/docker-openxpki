# Docker OpenXPKI testing

[OpenXPKI] certificate management in a Docker container.

## General Summary
This branch is just some screwing about with other database drivers that aren't workable for whatever reason.

The SQLite3 backend works in the init system, the database gets locked as soon as OpenXPKI tries to use it.

The Oracle backend *nearly* works in the init system, but it's not sensibly possible to distribute some OpenXPKI-required Oracle binaries in an image.

The DB2 backend has been ignored completely. The init system will accept DB2 environment variables but it won't do anything with them.

### Database configuration

* ``OXPKI_DB_TYPE``					- database name (acceps: `mariadb` (default), `mysql`, `postgresql`, <`db2`, `oracle`, `sqlite`>)
* ``OXPKI_DB_NAME``					- database name OR local path for `sqlite` database (default: `openxpki`)
* ``OXPKI_DB_HOST``					- database host name or IP
* ``OXPKI_DB_PORT``					- database port (default: `3306`)
* ``OXPKI_DB_USER``					- database user name (default: `openxpki`)
* ``OXPKI_DB_PASS``					- database user password (default: `openxpki`)
* ``OXPKI_DB_ROOT_USER``		- database `root` user
* ``OXPKI_DB_ROOT_PASS``		- database `root` password
* ``OXPKI_DB_MAX_RETRIES``	- database connection attempt limit (default: `30`)
* ``OXPKI_SQLITE_PATH``			- path in container for `sqlite` database (default: `/openxpki/database.sqlite3`)
* ``OXPKI_DEBUG``						- set the `--debug` argument on `openxpkictl`, see the [openxpkictl manpage][oxpki-manpage] for details
* ``OXPKI_DB_ORACLE_SID``		- SID for Oracle
* ``OXPKI_DB_ORACLE_FILE_DEST``	- used for creating Oracle PDB

##### `db2`
Not done.

##### `oracle`
The init system mostly works against Oracle 18c XE, but I can't make the database open. The larger problem is that the Oracle driver in OpenXPKI won't work without binaries from Oracle, which I can't build into an image.

It also makes a mess of `cont-init.d/20-database`, requiring exceptions in the common logic that works for the other backends. This would need a re-think if it were to be used. 

##### `sqlite`
The `sqlite` backend is functional but the database gets locked as soon as OpenXPKI tries to use it. Either there's some config I've missed or OpenXPKI and SQLite just don't play nice. I don't know which, I've not looked into it.

## Links
GitHub: https://github.com/moonbuggy/docker-openxpki

Docker Hub: https://hub.docker.com/r/moonbuggy2000/openxpki

usql-static: https://github.com/moonbuggy/usql-static


[OpenXPKI]: https://www.openxpki.org/ (OpenXPKI)
[oxpki-docs]: http://openxpki.readthedocs.io/en/latest/ (OpenXPKI manual)
[oxpki-quickstart]: https://openxpki.readthedocs.io/en/latest/quickstart.html (OpenXPKI quickstart)
[oxpki-config]: https://github.com/openxpki/openxpki-config/ (openxpki-config)
[oxpki-sampleconfig]: https://github.com/openxpki/openxpki-config/blob/community/contrib/sampleconfig.sh (sampleconfig.sh)
[oxpki-manpage]: https://manned.org/openxpkictl/f9b633c3
[usql-static]: https://github.com/moonbuggy/usql-static (usql-static)
