#! /bin/bash

path="$(dirname "$0")"
cd "$path" || exit 1

# Command line arguments:
# 1: estate "Challenger" or "NUIG"
# 2: start date "DD-MM-YYYY"
# 3: end date "DD-MM-YYYY"
# 4: number time steps per hour

estate="$1"
dateS="$2"
dsy="${dateS:6:4}"
dsm="${dateS:3:2}"
dsd="${dateS:0:2}"
dateF="$3"
dfy="${dateF:6:4}"
dfm="${dateF:3:2}"
dfd="${dateF:0:2}"
nsteps="$4"

if [ "$estate" == "Challenger" ]; then
    echo "not currently supported"
    exit 1
elif [ "$estate" == "NUIG" ]; then
    echo "NUIG_Network7_No_01_AHU103_Ctrls_01_Mixed_Air_Temp__DATALOG1,${dsy}-${dsm}-${dsd}T00:00:00,${dfy}-${dfm}-${dfd}T23:59:59" > var2get
fi

err=false
./chips -g
python3 mkcalcsv.py "$nsteps"
if [ $? -ne 0 ]; then 
    err=true
    echo "Error: No data available"
fi

if [ "$estate" == "NUIG" ]; then
    rm NUIG_Network7_*
fi

if $err; then exit 1; fi
