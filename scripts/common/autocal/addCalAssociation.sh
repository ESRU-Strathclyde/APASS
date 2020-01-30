#! /bin/bash

# This script associates tdfa file 'model/dbs/measured_data.csv' (output from createTdfa.py) with ESP-r model 'model/cfg/*.cfg'.
# Currently, functionality is hard coded per estate ('Challenger' and 'NUIG').
# Assumes that current directory is a job directory with a model in it.

estate="$1"
index="$2"

if [ "$estate" == 'NUIG' ]; then
  prj -file model/cfg/*.cfg -mode script << XXX
b
m
b
r
e

b
${index}
a
y
-
-
!


-
-
XXX
fi