FROM debian:stretch

# Build-time arguments. See README.md for details.
ARG REBUILD=1
ARG COTURN_UID=3478
ARG COTURN_GID=3478
ARG TLS_GID
ARG COTURN_DOMAIN
ARG COTURN_PORT=3478

# Update initial image.
RUN apt-get update && apt-get upgrade -y

# Get Synapse and related packages.
COPY get-coturn.sh /tmp/get-coturn.sh
RUN chmod 555 /tmp/get-coturn.sh && /tmp/get-coturn.sh && rm /tmp/get-coturn.sh

# Set up expected volume.
RUN mkdir /secrets /tls && touch /secrets/no-volume /tls/no-volume

# Set up user and environment.
COPY setup-coturn-env.sh /tmp/setup-coturn-env.sh
RUN chmod 555 /tmp/setup-coturn-env.sh && /tmp/setup-coturn-env.sh && rm /tmp/setup-coturn-env.sh

# Minimize final image size.
#RUN apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Main launch script.
COPY coturn.sh /coturn.sh
RUN chmod 555 /coturn.sh
CMD /coturn.sh
