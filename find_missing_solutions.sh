#!/bin/bash
find . -type f -name "go.mod" -path "*/[0-9]*" | \
  sed 's|/go.mod||' | \
  sed 's|^\./||' | \
  sort | \
  while read exercise; do
    if [ ! -f "$exercise/solution/main.go" ]; then
      echo "$exercise"
    fi
  done
