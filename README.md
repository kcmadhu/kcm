# kcm

## Sample Oracle database read

[`database-read.php`](./database-read.php) uses PDO_OCI to connect to Oracle and
print up to 10 rows from a `users` table as JSON. The default connection treats
`OD` as the Oracle SID. Update the `SELECT` statement to match your table and
columns.

Set connection details through environment variables, then run it from the command
line:

```sh
DB_DSN='oci:dbname=(DESCRIPTION=(ADDRESS=(PROTOCOL=TCP)(HOST=db-host)(PORT=1521))(CONNECT_DATA=(SID=OD)))' \
DB_USER='app_user' \
DB_PASSWORD='your_password' \
php database-read.php
```

The PDO_OCI driver and Oracle client libraries must be installed and enabled in
PHP. If `OD` is a service name rather than a SID, replace `(SID=OD)` with
`(SERVICE_NAME=OD)` in `DB_DSN`. The script defaults to localhost on port 1521
with SID `OD`; set `DB_USER` and `DB_PASSWORD` to your Oracle credentials.