#! /bin/sh

./main.py /mnt/APASS 2>&1 1>>"$(tail -1 .SQL.txt)" &
