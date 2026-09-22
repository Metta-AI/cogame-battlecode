# Java rules and recorded replays require each floating-point operation to round
# separately. ARM64 Clang otherwise contracts multiply/add into one operation.
switch("passC", "-ffp-contract=off")
