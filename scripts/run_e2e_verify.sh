#!/bin/bash
set -e

echo "=== Cleaning previous snapshots ==="
rm -rf tmp/snapshots
mkdir -p tmp/snapshots

echo "=== Running Playwright E2E Tests ==="
npx playwright test

echo "=== Snapshots Generated ==="
ls -lh tmp/snapshots/
echo "==========================="
echo "Successfully completed E2E execution and generated snapshots."
