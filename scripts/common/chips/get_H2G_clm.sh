#! /bin/bash

path="$(dirname $0)"
cd $path

# Command line arguments:
# 1: estate "Challenger" or "NUIG"
# 2: start date "DD-MM-YYYY"
# 3: end date "DD-MM-YYYY"

estate="$1"
dateS="$2"
dsy="${dateS:6:4}"
dsm="${dateS:3:2}"
dsd="${dateS:0:2}"
dateF="$3"
dfy="${dateF:6:4}"
dfm="${dateF:3:2}"
dfd="${dateF:0:2}"

if [ "$estate" == "Challenger" ]; then
    echo "CHA_METEO_RAY-GLOB,${dsy}-${dsm}-${dsd}T00:00:00,${dfy}-${dfm}-${dfd}T23:59:59
CHA_METEO_Temperature,${dsy}-${dsm}-${dsd}T00:00:00,${dfy}-${dfm}-${dfd}T23:59:59
CHA_METEO_RAY-DIR,${dsy}-${dsm}-${dsd}T00:00:00,${dfy}-${dfm}-${dfd}T23:59:59
CHA_METEO_Humidity,${dsy}-${dsm}-${dsd}T00:00:00,${dfy}-${dfm}-${dfd}T23:59:59" > var2get
    cp Challenger.clmvar_template Challenger.clmvar
elif [ "$estate" == "NUIG" ]; then
    echo "NUIG_AspectGroup_Weather_Current_Wind_Speed,${dsy}-${dsm}-${dsd}T00:00:00,${dfy}-${dfm}-${dfd}T23:59:59
NUIG_AspectGroup_Weather_Current_Humidity,${dsy}-${dsm}-${dsd}T00:00:00,${dfy}-${dfm}-${dfd}T23:59:59
NUIG_AspectGroup_Weather_Current_Temperature,${dsy}-${dsm}-${dsd}T00:00:00,${dfy}-${dfm}-${dfd}T23:59:59" > var2get
    cp NUIG.clmvar_template NUIG.clmvar
fi

err=false
./chips -g
python3 mkespclm.py
if [ $? -ne 0 ]; then 
    err=true
    echo "Error: No data available"
fi

if [ "$estate" == "Challenger" ]; then
    if ! $err; then
        if [ -f Challenger.clm ]; then rm Challenger.clm; fi
        python3 combine_clm_Challenger.py
        clm -file Challenger.clm -act asci2bin silent Challenger_comb.clm.a
    fi
    rm Challenger.clm.a Challenger.clmvar CHA_METEO_*
elif [ "$estate" == "NUIG" ]; then
    if ! $err; then
        if [ -f NUIG.clm ]; then rm NUIG.clm; fi
        python3 combine_clm_NUIG.py
        clm -file NUIG.clm -act asci2bin silent NUIG_comb.clm.a
    fi
    rm NUIG.clm.a NUIG.clmvar NUIG_AspectGroup_Weather_Current_*
fi

if $err; then exit 1; fi
