#! /bin/bash

estate="$1"
preset_letter="$2"

cd model/cfg || exit 1

if [ "$estate" == 'NUIG' ]; then
  prj -file ./*.cfg -mode script <<XXX
m
v
y
${preset_letter}
-
1
a
y
a
c
a
a
-
f
-
-
XXX
fi