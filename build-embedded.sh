#!/bin/bash

# Stop on error
set -e

mkdir -p .cmake-build
cd .cmake-build
cmake -G 'Ninja' ../
ninja
