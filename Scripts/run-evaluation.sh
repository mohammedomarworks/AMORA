#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
cd "$DIR"

MODE="${1:---all}"
if [ $# -gt 0 ]; then
    shift
fi
EXTRA_ARGS=("$@")

echo "🧠 AMORA — Evaluation & Model Comparison V1"
echo "============================================"

if [ "$MODE" = "--test" ] || [ "$MODE" = "test" ]; then
    echo "🧪 Running full evaluation test suite via XCTest..."
    swift test --filter AmoraEvaluationTests
    exit 0
fi

echo "🔨 Building AMORA binary..."
swift build

echo "📊 Executing Evaluation Runner..."
case "$MODE" in
    --router|router)
        .build/debug/AMORA --eval --router "${EXTRA_ARGS[@]}"
        ;;
    --real|real)
        .build/debug/AMORA --eval --real "${EXTRA_ARGS[@]}"
        ;;
    --mock|mock)
        .build/debug/AMORA --eval --mock "${EXTRA_ARGS[@]}"
        ;;
    --production|production)
        .build/debug/AMORA --eval --production "${EXTRA_ARGS[@]}"
        ;;
    *)
        echo "Running complete evaluation suite across all modes..."
        echo ""
        echo "--- 1. Deterministic Router Evaluation ---"
        .build/debug/AMORA --eval --router "${EXTRA_ARGS[@]}"
        echo ""
        echo "--- 2. End-to-End Production Pipeline Evaluation ---"
        .build/debug/AMORA --eval --production "${EXTRA_ARGS[@]}"
        echo ""
        echo "--- 3. Standalone Real Local Model Evaluation ---"
        .build/debug/AMORA --eval --real "${EXTRA_ARGS[@]}"
        ;;
esac
