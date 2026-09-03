FROM dart:3.12.0 AS build

WORKDIR /workspace
COPY packages/compendium_core /workspace/packages/compendium_core
COPY server /workspace/server
RUN printf '%s\n' \
    'name: callers_compendium_server_workspace' \
    'publish_to: none' \
    'environment:' \
    '  sdk: ^3.12.0' \
    'workspace:' \
    '  - packages/compendium_core' \
    '  - server' > /workspace/pubspec.yaml
COPY pubspec.lock /workspace/pubspec.lock
RUN dart pub get
RUN dart build cli \
    --target server/bin/athenaeum.dart \
    --output /out

FROM dart:3.12.0

RUN mkdir -p /var/lib/athenaeum \
    && chown -R nobody:nogroup /var/lib/athenaeum
COPY --from=build /out/bundle /opt/athenaeum

USER nobody
VOLUME ["/var/lib/athenaeum"]
EXPOSE 33333
ENTRYPOINT ["/opt/athenaeum/bin/athenaeum"]
CMD ["--data-dir", "/var/lib/athenaeum"]
