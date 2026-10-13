#!/bin/sh
# Rebuilds the checklist and stages it for the laptop copy (docs\Mangao-Testing-Checklist.docx).
set -e
cd "$(dirname "$0")"
node build.js
mkdir -p /mnt/user-data/outputs/mangao-system/docs
cp Mangao-Testing-Checklist.docx /mnt/user-data/outputs/mangao-system/docs/Mangao-Testing-Checklist.docx
