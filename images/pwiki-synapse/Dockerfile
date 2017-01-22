FROM debian:stretch

# Build-time arguments. See README.md for details.
ARG REBUILD=1
ARG SYNAPSE_UID=8449
ARG SYNAPSE_GID=8449
ARG TLS_GID
ARG SYNAPSE_DOMAIN=theportalwiki.com
ARG SYNAPSE_PORT=8449
ARG COTURN_DOMAIN
ARG COTURN_PORT=3478

# Update initial image.
RUN apt-get update && apt-get upgrade -y

# Get Synapse and related packages.
COPY get-synapse.sh /tmp/get-synapse.sh
RUN chmod 555 /tmp/get-synapse.sh && /tmp/get-synapse.sh && rm /tmp/get-synapse.sh

# Set up expected volumes.
RUN mkdir /secrets /tls /synapse-media && touch /secrets/no-volume /tls/no-volume /synapse-media/no-volume

# Set up user and environment.
COPY setup-synapse-env.sh /tmp/setup-synapse-env.sh
RUN chmod 555 /tmp/setup-synapse-env.sh && /tmp/setup-synapse-env.sh && rm /tmp/setup-synapse-env.sh

# Copy scripts.
COPY bin/generate-secrets /bin/generate-secrets
COPY bin/register /bin/register
RUN chmod 555 /bin/generate-secrets /bin/register

# Minimize final image size.
#RUN apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Main launch script.
COPY synapse.sh /synapse.sh
RUN chmod 555 /synapse.sh
CMD /synapse.sh
