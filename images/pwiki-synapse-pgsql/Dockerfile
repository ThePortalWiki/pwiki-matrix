FROM postgres

# Set up expected volume.
RUN mkdir /secrets && touch /secrets/no-volume

# SQL initialization script.
COPY init-synapse-db.sh /docker-entrypoint-initdb.d/
RUN chmod 555 /docker-entrypoint-initdb.d/init-synapse-db.sh

# Container entrypoint; overrides the built-in one to inject the password environment variable.
ENV POSTGRESQL_ENTRYPOINT=/docker-entrypoint.sh
RUN bash -c '[ -x "$POSTGRESQL_ENTRYPOINT" ] || (echo "Cannot find entrypoint." >&2; exit 1)'
COPY /synapse-pgsql.sh /
RUN chmod 555 /synapse-pgsql.sh
ENTRYPOINT ["/synapse-pgsql.sh"]
CMD ["postgres"]
