FROM postgres:16-bookworm

# Copy SQL and loop script
# COPY generator-v2.sql /sql/generator-v2.sql
COPY insert_loop.sh /usr/local/bin/insert_loop.sh

RUN chmod +x /usr/local/bin/insert_loop.sh

# psql will read connection info from env:
#   PGHOST, PGPORT, PGDATABASE, PGUSER, PGPASSWORD
ENV PGPORT=5432 \
    PGDATABASE=postgres \
    PGUSER=postgres

# INTERVAL_SECONDS controls frequency
ENV INTERVAL_SECONDS=5

ENTRYPOINT ["/usr/local/bin/insert_loop.sh"]