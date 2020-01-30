#! /bin/bash

# This script creates a simulation preset for calibration in model 'model/cfg/*.cfg'.
# Assumes that current directory is a job directory with a model in it.

preset_name="$1"
preset_letter="$2"
num_startup="$3"
num_timeStep="$4"
start_day_month="$5"
end_day_month="$6"
is_existing="$7"
if "$is_existing"; then
  a="+
${preset_name}
${preset_letter}"
else
  a="y
${preset_name}"
fi

prj -file model/cfg/*.cfg -mode script << XXX
b
m
s
a
${a}
c
${num_startup}
d
${num_timeStep}
g
${start_day_month}
${end_day_month}
p
a
-
!


-
-
XXX