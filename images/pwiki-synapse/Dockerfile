FROM debian:stretch

# Build-time arguments. See README.md for details.
ARG REBUILD=1
ARG SYNAPSE_UID=8449
ARG SYNAPSE_GID=8449
ARG TLS_GID
ARG SYNAPSE_DOMAIN=theportalwiki.com
ARG SYNAPSE_PORT=8449

# Update initial image.
RUN apt-get update && apt-get upgrade -y

# Get Synapse and related packages.
COPY get-synapse.sh /tmp/get-synapse.sh
RUN chmod +x /tmp/get-synapse.sh && /tmp/get-synapse.sh && rm /tmp/get-synapse.sh

# Set up volumes.
RUN mkdir -m 750 /synapse /tls /synapse-media
# Only /synapse is an image volume.
VOLUME /synapse

# Set up user.
COPY setup-synapse-env.sh /tmp/setup-synapse-env.sh
RUN chmod +x /tmp/setup-synapse-env.sh && /tmp/setup-synapse-env.sh && rm /tmp/setup-synapse-env.sh

# Copy initialization script.
COPY initialize-synapse-onetime.sh /initialize-synapse-onetime.sh
RUN chmod +x /initialize-synapse-onetime.sh


# Minimize final image size.
#RUN apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Run command specification.
COPY synapse.sh /synapse.sh
RUN chmod 555 /synapse.sh
CMD /synapse.sh
