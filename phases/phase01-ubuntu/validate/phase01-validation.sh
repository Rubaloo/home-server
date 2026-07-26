#!/bin/bash
# Master validation script
echo "Running Phase 01 validation..."
for script in check-*.sh; do
    echo "Validating: $script"
    ./"$script"
done
echo "Validation completed!"
