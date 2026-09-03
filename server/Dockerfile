FROM dart:3.12.0 AS build

WORKDIR /workspace
COPY pubspec.yaml pubspec.lock /workspace/
COPY packages/compendium_core /workspace/packages/compendium_core
COPY server /workspace/server
RUN dart pub get
RUN dart compile exe server/bin/athenaeum.dart -o /out/athenaeum

FROM dart:3.12.0

RUN mkdir -p /var/lib/athenaeum \
    && chown -R nobody:nogroup /var/lib/athenaeum
COPY --from=build /out/athenaeum /usr/local/bin/athenaeum

USER nobody
VOLUME ["/var/lib/athenaeum"]
EXPOSE 33333
ENTRYPOINT ["/usr/local/bin/athenaeum"]
CMD ["--data-dir", "/var/lib/athenaeum"]
