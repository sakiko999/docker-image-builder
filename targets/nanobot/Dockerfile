ARG BASE_IMAGE
FROM $BASE_IMAGE

ARG UPSTREAM_TAG
ARG UPSTREAM_SHA
ARG OVERLAY_SHA

LABEL org.opencontainers.image.source="https://github.com/HKUDS/nanobot"
LABEL org.opencontainers.image.version="$UPSTREAM_TAG"
LABEL org.opencontainers.image.revision="$UPSTREAM_SHA"
LABEL org.opencontainers.image.vendor="sakiko999"
LABEL io.github.sakiko999.nanobot.overlay-revision="$OVERLAY_SHA"

COPY --chmod=0755 targets/nanobot/entrypoint.sh /usr/local/bin/nanobot-overlay-entrypoint
COPY --chmod=0755 targets/nanobot/healthcheck.sh /usr/local/bin/nanobot-healthcheck
COPY targets/nanobot/config/ /opt/nanobot-overlay/config/

EXPOSE 18790
EXPOSE 8765
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 CMD ["/usr/local/bin/nanobot-healthcheck"]

ENTRYPOINT ["/usr/local/bin/nanobot-overlay-entrypoint"]
CMD ["gateway"]
