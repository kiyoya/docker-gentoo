#!/bin/sh
# @(#) Script to setup a shell within containers.

exec >/dev/tty 2>/dev/tty </dev/tty
su - "$@"
