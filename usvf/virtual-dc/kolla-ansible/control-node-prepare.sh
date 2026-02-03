#!/bin/bash
set -eux

sudo ip addr add 10.100.0.254/32 dev lo1
