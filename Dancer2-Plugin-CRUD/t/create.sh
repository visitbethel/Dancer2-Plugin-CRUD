 [ -e db/db ] && rm db/db; sqlite3 db/db < db/create.sql 
dbicdump -Ilib -o use_namespaces=1 -o dump_directory=./lib -o components='["InflateColumn::DateTime"]' -o debug=1 -o use_moose=1 -o overwrite_modifications=1 CRUD 'dbi:SQLite:./db/db'
