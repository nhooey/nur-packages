#!/bin/sh
# Launcher for a nix-darwin launchd job, installed by services.background-items
# under the name System Settings shows for the job (Login Items & Extensions
# names an unsigned job after the program its plist runs). The job's own
# program and arguments follow as "$@". This file is a copy outside /nix, as
# daemons start before /nix is mounted; it waits for the store, then execs the
# job's command in its own process, so launchd's PID and signals reach it.
/bin/wait4path /nix/store
exec "$@"
