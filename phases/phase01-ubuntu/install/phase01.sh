#!/bin/bash
# Master script to run all phase01 installation steps
echo "Running Phase 01 - Ubuntu Setup..."
for script in [0-9][0-9]-*.sh; do
    echo "Executing: $script"
    ./"$script"
done
echo "Phase 01 completed!"
