## Emits the JS wire-constants block (src/battlecode/wire_constants.nim) on
## stdout. The static replay-viewer bundle cannot run a server-side splice, so
## Dockerfile.replay-viewer runs this to write dist/wire_constants.js and
## injects a <script src> for it into index.html — same constants, same
## source, different delivery.
import ../src/battlecode/wire_constants

echo WireConstantsJs
