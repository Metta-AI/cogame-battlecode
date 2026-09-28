FROM eclipse-temurin:21-jdk-jammy AS base
RUN apt-get update && apt-get install -y --no-install-recommends python3 python3-venv git ca-certificates \
    && rm -rf /var/lib/apt/lists/*
RUN python3 -m venv /venv && /venv/bin/pip install pydantic==2.12.5 jinja2==3.1.6 aiohttp==3.13.3
WORKDIR /workspace
FROM base AS build
COPY tools/official/runner.py tools/official/sources.json tools/official/OfficialMatch*.java /workspace/tools/official/
RUN /venv/bin/python -c 'import sys; sys.path.insert(0, "tools/official"); from runner import CATALOG, build_player; from pathlib import Path; build=Path("/opt/official"); build.mkdir(); [build_player(p, build, Path("/opt/java/openjdk/bin"), build / "archives" / p.id) for p in CATALOG.players if p.redistributable]'
RUN /venv/bin/python - <<'PY'
import shutil, sys
from pathlib import Path
sys.path.insert(0, "tools/official")
from runner import CATALOG
for player in CATALOG.players:
    if not player.redistributable:
        continue
    archive = Path("/opt/official/archives") / player.id
    selected = Path("/opt/official/sources") / player.id
    selected.mkdir(parents=True)
    for relative in [player.source, player.license_file] + (["jinja.py", "helpers"] if player.generate else []):
        source = archive / relative
        target = selected / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        if source.is_dir():
            shutil.copytree(source, target)
        else:
            shutil.copyfile(source, target)
shutil.rmtree("/opt/official/archives")
PY
COPY tools/official/server.py tools/official/viewer.html /workspace/tools/official/
COPY LICENSE NOTICE /workspace/
FROM base AS runtime
COPY --from=build /opt/official /opt/official
COPY --from=build /workspace /workspace
CMD ["/venv/bin/python", "/workspace/tools/official/server.py"]
