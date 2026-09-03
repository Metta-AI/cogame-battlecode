# ONE image, TWO entrypoints: /bin/battlecode (the game server) and
# /bin/battlecode-player (the thin seat registrar). The policy set is
# env-switched inside this same image (PLAYER_PROMPT vs PLAYER_SCRIPTED),
# which is what keeps a champion and a scripted filler byte-identical apart
# from their environment.
#
# NO JDK, NO JRE, NO JAVA, NO NODE in any stage. The Battlecode engine exists
# in this repo only as the CI-only `parity-oracle` job (docs/PARITY.md); the
# rules that run here are the Nim port in src/battlecode/.
FROM debian:bookworm-slim AS build

RUN apt-get update && \
  apt-get install -y --no-install-recommends \
    build-essential \
    ca-certificates \
    curl \
    git \
    xz-utils && \
  rm -rf /var/lib/apt/lists/*

RUN if [ "$(dpkg --print-architecture)" = "amd64" ]; then \
    curl -fsSL \
      -o /usr/local/bin/nimby \
https://github.com/treeform/nimby/releases/download/0.1.26/nimby-Linux-X64; \
  elif [ "$(dpkg --print-architecture)" = "arm64" ]; then \
    curl -fsSL \
      -o /usr/local/bin/nimby \
https://github.com/treeform/nimby/releases/download/0.1.26/nimby-Linux-ARM64; \
  else \
    echo "unsupported arch: $(dpkg --print-architecture)" && exit 1; \
  fi && \
  chmod +x /usr/local/bin/nimby && \
  nimby use 2.2.4

ENV PATH="/root/.nimby/nim/bin:$PATH"

WORKDIR /workspace/battlecode
COPY nimby.lock .
RUN nimby --global sync nimby.lock

COPY . .
# The committed nim.cfg pins the AUTHOR's package paths; rebuild it from this
# machine's synced tree, exactly as ci.yml does.
RUN rm -f nim.cfg && \
  for pkg in /root/.nimby/pkgs/*; do \
    if [ -d "$pkg/src" ]; then echo "--path:\"$pkg/src\"" >> nim.cfg; \
    else echo "--path:\"$pkg\"" >> nim.cfg; fi; \
  done && \
  echo '--path:"src"' >> nim.cfg

ARG NimFlags="-d:release -d:useMalloc --opt:speed --stackTrace:on"
ARG SIM_SOURCES_STAMP=""
RUN nim c $NimFlags --threads:on -d:bcSimSourcesStamp="${SIM_SOURCES_STAMP}" \
      --nimcache:/tmp/battlecode-nimcache \
      --out:battlecode src/battlecode.nim && \
    nim c $NimFlags \
      --nimcache:/tmp/battlecode-player-nimcache \
      --out:battlecode-player src/battlecode_player.nim

# ---------------------------------------------------------------------------
# Runtime. Debian slim + libcurl; nothing else.
# ---------------------------------------------------------------------------
FROM debian:bookworm-slim AS runtime

RUN apt-get update && \
  apt-get install -y --no-install-recommends ca-certificates libcurl4 && \
  rm -rf /var/lib/apt/lists/*

WORKDIR /workspace/battlecode
COPY --from=build /workspace/battlecode/battlecode /bin/battlecode
COPY --from=build /workspace/battlecode/battlecode-player /bin/battlecode-player
COPY --from=build /workspace/battlecode/data ./data
COPY --from=build /workspace/battlecode/coworld_manifest_template.json ./

CMD ["/bin/battlecode"]

# `compose.yaml`'s player service targets this stage; it is the SAME image
# contents, so a champion and a filler differ only by environment.
FROM runtime AS player
CMD ["/bin/battlecode-player"]
