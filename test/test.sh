#!/bin/bash
# Comprehensive project test suite
set -e

echo "--- NZI: STARTING COMPREHENSIVE TEST SUITE ---"

echo ""
echo "--- 1. LINTING XML DOCUMENTS ---"
./test/lint.sh

echo ""
echo "--- 2. RUNNING PYTHON UNIT TESTS ---"
./test/units.sh

echo ""
echo "--- 3. RUNNING FILESYSTEM & UNIVERSE TESTS ---"
./test/fs.sh

echo ""
echo "--- 4. RUNNING NEOVIM E2E TESTS ---"
./test/e2e.sh

echo ""
echo "--- ALL TESTS PASSED SUCCESSFULLY ---"
