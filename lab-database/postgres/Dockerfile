FROM postgres:15-alpine

# Initialize the demo database schema when the container starts for the first time.
COPY init.sql /docker-entrypoint-initdb.d/init.sql
