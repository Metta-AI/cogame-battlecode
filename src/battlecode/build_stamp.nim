## The SIM SOURCES STAMP, baked in at compile time.
##
## `tools/sim_sources_stamp.sh` hashes every Nim input the sim is compiled
## from plus `nimby.lock`; `tools/build_replay_viewer.sh` passes it as
## `-d:bcSimSourcesStamp` and the wasm bundle exports it, so CI can recompute
## the hash at HEAD and fail a bundle built from older sim sources. The
## `GameVersion` tripwire only catches drift somebody remembered to bump;
## this catches the rest.

const bcSimSourcesStamp* {.strdefine.} = ""
