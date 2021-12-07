#! /bin/bash

# CIBSE Thermal Comfort Performance Assessment Method - ESP-r implementation
# Version 3.1 of March 2019.

# Implementation-specific error codes:
# 201 - could not create temporary directory
# 202 - problem with simulation preset
# 203 - model name is empty
# 204 - other problem with model (error output from esp-query should specify)
# 205 - no zone control

# Set up defaults.
building=""
results_file="simulation_results"
start="1 1"
finish="31 12"
year="2000"
timesteps=-1
startup=5
preset=""
tmp_dir="./tmp"
report_final="./report.pdf"
detailed_report_final="./detailed_report.pdf"
JSON="./data.json"
information=false
verbose=false
preamble_file=""
do_simulation=true
do_detailed_report=false
# CFD_start_hour='1.0'
# CFD_finish_hour='24.99'
CFD_start_hour='6.0'
CFD_finish_hour='20.99'

# Get paths to call the various other scripts used by this program.
script_dir="$(dirname "$(readlink -f "$0")")"
common_dir="$script_dir/../../common"

# Parse command line.
while getopts ":hvf:p:t:s:d:r:R:j:P:U" opt; do
  case "$opt" in
    h) information=true;;
    v) verbose=true;;
    f) results_file="$OPTARG";;
    p) start="$(echo "$OPTARG" | awk -v FS='_' -v OFS=' ' '{print $1,$2}')"
       finish="$(echo "$OPTARG" | awk -v FS='_' -v OFS=' ' '{print $3,$4}')"
       year="$(echo "$OPTARG" | awk -v FS='_' -v OFS=' ' '{print $5}')";;
    t) timesteps="$OPTARG";;
    s) preset="$OPTARG";;
    d) tmp_dir="$OPTARG";;
    r) report_final="$OPTARG";;
    j) JSON="$OPTARG";;
    P) preamble_file="$OPTARG";;
    U) do_simulation=false;;
    R) do_detailed_report=true
       detailed_report_final="$OPTARG";;
    \?) echo "Error: unknown option -$OPTARG. Use option -h for help." >&2
        exit 107;;
    :) echo "Error: option -$OPTARG requires and argument." >&2
       exit 107;;
  esac
done
shift $((OPTIND-1))
building="$1"

if "$information" ; then
  echo
  echo " Usage: ./ISO7730.sh [OPTIONS] model-cfg-file"
  echo
  echo " ESP-r implementation of the CIBSE Thermal Comfort Performance Assessment Method."
  echo
  echo " Command line options: -h"
  echo "                          display help text and exit"
  echo "                          default: off"
  echo "                       -v"
  echo "                          verbose output to stdout"
  echo "                          default: off"
  echo "                       -f results-file"
  echo "                          file name of the simulation results (output from BPS), without extension"
  echo "                          simulation results will be called [results-file].res"
  echo "                          mass flow results will be called [results-file].mfr"
  echo "                          CFD results will be called [results-file].dfr"
  echo "                          default: ./simulation_results"
  echo "                       -p start-day_start-month_finish-day_finish-month_year"
  echo "                          start and end days of simulation period"
  echo "                          default: 1_1_31_12_2000"
  echo "                       -t timesteps"
  echo "                          number of timesteps per hour"
  echo "                          default: read from model"
  echo "                       -s simulation-preset"
  echo "                          name of the simulation preset to be run"
  echo "                          default:"
  echo "                       -d temporary-files-directory"
  echo "                          directory into which temporary files will be placed"
  echo "                          default: ./tmp"
  echo "                       -r pdf-report"
  echo "                          file name of the pdf report"
  echo "                          default: ./report.pdf"
  echo "                       -R detailed-pdf-report"
  echo "                          file name of a detailed pdf report, with added graphs"
  echo "                          default: no detailed report will be generated"
  echo "                       -j JSON-file"
  echo "                          file name of the json report"
  echo "                          default: ./data.json"
#  echo "                       -i model-image"
#  echo "                          image in .pdf, .png, .jpg or .eps format."
#  echo "                          default: PAM will automatically generate a wireframe image of the model"
  echo "                       -P preamble-file"
  echo "                          text in this file will be placed in the report before analysis outcomes"
  echo "                          default: none"
  echo "                       -U" 
  echo "                          Do not simulate and use existing results libraries"
  echo "                          default: off"
  echo
  echo " If a simulation preset is defined and present, it will override the period and time steps parameters."
  echo " If the simulation preset is not found this will not cause a fatal error; the PAM will use user-defined"
  echo " or default period and time steps for the simulation."

  exit 0
fi

# Check model exists.
if ! [ -f "$building" ]; then
  echo "Error: model not found." >&2
  exit 107
fi

# Set comfort criteria.
floor_criteria='13.0'
asym_criteria='5.0'
vertdT_criteria='7.0'
draught_criteria='15.0'
opt_criteria_min_sum='22.0'
opt_criteria_max_sum='25.0'
opt_criteria_min_win='21.0'
opt_criteria_max_win='23.0'
DMopt_daily_drift_criteria='1.0'
DMopt_weekly_drift_criteria='3.0'

# Check simluation period and timesteps.
check="$(echo "$start" | awk '{ if ($0 ~ /^[0-9]+ +[0-9]+$/) {print "yes"} }')"
if [ "$check" != "yes" ]; then
  echo "Error: invalid simulation start date." >&2
  exit 107
fi
check="$(echo "$finish" | awk '{ if ($0 ~ /^[0-9]+ +[0-9]+$/) {print "yes"} }')"
if [ "$check" != "yes" ]; then 
  echo "Error: invalid simulation finish date." >&2
  exit 107
fi
if [ "$timesteps" -eq -1 ]; then
  timesteps="$(awk -v mode="1" -f "$script_dir/get_simPreset_timesteps.awk" "$building")"
fi
check="$(echo "$timesteps" | awk '{ if ($0 ~ /^[0-9]+$/) {print "yes"} }')"
if [ "$check" != "yes" ]; then
  echo "Error: invalid number of timesteps per hour." >&2
  exit 107
fi

# Check preamble file exists.
if ! [ "X$preamble_file" == "X" ]; then
  if ! [ -f "$preamble_file" ]; then
    echo "Error: preamble file not found." >&2
    exit 107
  fi
fi



if $verbose; then echo "***** CIBSE PAM START"; fi

# Test if tmp directory exists.
if [ ! -d "$tmp_dir" ]; then
  if $verbose; then echo " Temporary directory \"$tmp_dir\" not found, attempting to create....."; fi
  mkdir "$tmp_dir"
  if [ -d "$tmp_dir" ]; then
    if $verbose; then echo " .....done."; fi
  else
    if $verbose; then echo ".....failed."; fi
    echo "Error: could not create temporary files directory." >&2
    exit 201
  fi
#else
#  rm -f $tmp_dir/*
fi

# Create progress file.
echo '2' > "$tmp_dir/progress.txt"

# ESP-r seems to have problems if locations have a dot in
# front of them; check for this and remove it.
if [ "${results_file:0:2}" == "./" ]; then
  results_file="${results_file:2}"
fi
if [ "${tmp_dir:0:2}" == "./" ] && ! [ "$tmp_dir" == "./" ]; then
  tmp_dir="${tmp_dir:2}"
fi

# Currently, res asks a question if the cfg file is not in the directory from
# which it is called. Unless this is accounted for, it will break
# scripted results recovery if it happens. We get around this by forcing
# res to ask the question. So we need to check if the cfg file is in
# the local directory; if it is, we need go up one directory level when
# invoking res.
# TODO - This is a pain in the ass, and should probably be disabled in
# script mode.
# Also need to do this for bps so the library knows where to look for the
# model config file.
up_one=""
building_base="$(basename "$building")"
building_dir="$(dirname "$building")"
if [ "$building_base" == "$building" ] || [ "./$building_base" == "$building" ]; then
  up_one="${PWD##*/}"
fi

report="$tmp_dir/report.tex"

if "$do_detailed_report"; then
  detailed_report="$tmp_dir/detailed_report.tex"
fi



# *** CHECK MODEL ***

# Get model reporting variables, check values.
"$common_dir/esp-query/esp-query.py" -o "$tmp_dir/query_results.txt" "$building" "model_name" "model_description" "number_zones" "CFD_domains" "zone_control" "zone_setpoints" "MRT_sensors" "MRT_sensor_names" "afn_network" "zone_names" "zone_floor_surfs" "uncertainties_file" "ctm_network" "number_ctm"

if [ "$?" -ne 0 ]; then
  echo "Error: model reporting script failed." >&2
  exit 101
fi

# Check model name.
model_name="$(awk -f "$common_dir/esp-query/processOutput_getModelName.awk" "$tmp_dir/query_results.txt")"
if [ "X$model_name" == "X" ]; then
# This really should be impossible, but check anyway.
  echo "Error: model name is empty." >&2
  exit 203
fi

# Check number of zones.
number_zones="$(awk -f "$common_dir/esp-query/processOutput_getNumZones.awk" "$tmp_dir/query_results.txt")"
if [ "X$number_zones" == "X" ] || [ "$number_zones" -eq 0 ]; then
  echo "Error: no thermal zones found in this model." >&2
  exit 102
fi

# Assemble array of zone indices.
i=0
while [ "$i" -lt "$number_zones" ]; do
  array_zone_indices[i]="$i"
  ((i++))
done

# Assemble array of zone names.
zone_names="$(awk -f "$common_dir/esp-query/processOutput_getSpaceSeparatedZoneNames.awk" "$tmp_dir/query_results.txt")"
array_zone_names=($zone_names)

# Check zone control.
zone_control="$(awk -f "$common_dir/esp-query/processOutput_getZoneControl.awk" "$tmp_dir/query_results.txt")"
if [ "$zone_control" == "0" ]; then
  echo "Error: no heating or cooling detected in this model." >&2
  exit 205
fi

# Check for afn network.
afn_network="$(awk -f "$common_dir/esp-query/processOutput_getAFNnetwork.awk" "$tmp_dir/query_results.txt")"
if [ "X$afn_network" == "X" ]; then
  is_afn=false
else
  is_afn=true
fi

# Check for ctm network and number of contaminants.
ctm_network="$(awk -f "$common_dir/esp-query/processOutput_getCTMnetwork.awk" "$tmp_dir/query_results.txt")"
number_ctm="$(awk -f "$common_dir/esp-query/processOutput_getNumCTM.awk" "$tmp_dir/query_results.txt")"
if [ "X$ctm_network" == "X" ] || [ "$number_ctm" -ne "1" ]; then
  is_1ctm=false
else
  is_1ctm=true
fi

# Check for MRT sensors.
# While we're here, assemble an array mapping sensor indices to zones,
# and an array of indices for looping over sensor arrays.
MRT_sensors="$(awk -f "$common_dir/esp-query/processOutput_getSpaceSeparatedMRTsensors.awk" "$tmp_dir/query_results.txt")"
array_MRT_sensors=($MRT_sensors)
is_MRT=false
number_MRT_sensors=0
number_zones_with_MRTsensors=0
i_zone=0
i_ind=0
j=0
for n in "${array_MRT_sensors[@]}"; do
  ((i_zone++))
  if [ "$n" -gt 0 ]; then 
    if ! $is_MRT; then is_MRT=true; fi
    ((number_MRT_sensors+=n))
    ((number_zones_with_MRTsensors++))
    array_zones_with_MRTsensors[j]="$i_zone"
    ((j++))
    i=0
    while [ "$i" -lt "$n" ]; do
      array_sensor_zones=(${array_sensor_zones[@]} $i_zone)
      array_sensor_indices[i_ind]="$i_ind"
      ((i_ind++))
      ((i++))
    done
  fi
done
if ! $is_MRT; then
  echo "Error: no occupant locations detected in this model." >&2
  exit 103
fi

# Assemble array of MRT sensor names.
MRTsensor_names="$(awk -f "$common_dir/esp-query/processOutput_getSpaceSeparatedAllMRTsensorNames.awk" "$tmp_dir/query_results.txt")"
array_MRTsensor_names=($MRTsensor_names)

# Check for CFD domains.
CFD_domains="$(awk -f "$common_dir/esp-query/processOutput_getSpaceSeparatedCFDdomains.awk" "$tmp_dir/query_results.txt")"
array_CFD_domains=($CFD_domains)
is_CFD=false
is_CFDandMRT=false
CFDdomain_count=0
j=0
number_zones_with_CFDandMRT=0
for i in "${array_zone_indices[@]}"; do
  n="${array_CFD_domains[i]}"
  if [ "$n" -gt 1 ]; then
    is_CFD=true
    ((CFDdomain_count++))
    array_zone_CFDdomain_numbers[i]="$CFDdomain_count"
    m="${array_MRT_sensors[i]}"
    if [ "$m" -gt 0 ]; then
      is_CFDandMRT=true
      array_zones_with_CFDandMRT[j]="$((i+1))"
      ((j++))
      ((number_zones_with_CFDandMRT++))
    fi
  else
    array_zone_CFDdomain_numbers[i]='0'
  fi  
done

# Check CFD contaminants.
CFD_contam="$("$common_dir/esp-query/esp-query.py" "$building" "CFD_contaminants")"

# Get results file location, simulation period, timesteps and startup days if a simulation preset is defined.
sim_results_preset=""
mf_results_preset=""
cfd_results_preset=""
if ! [ "X$preset" == "X" ]; then

# Check if simulation preset exists. If it doesn't, fall back on default values.
  preset_check="$(awk -v preset="$preset" -f "$script_dir/check_simPreset_exists.awk" "$building")"
  if  [ "$preset_check" == "0" ]; then
    echo "Warning: simulation preset \"$preset\" not found, using default simulation setup."
    preset=""

  else
    sim_results_preset="$(awk -v mode="$preset_check" -v preset="$preset" -f "$script_dir/get_simPreset_resFile.awk" "$building")"
    if [ "X$sim_results_preset" == "X" ]; then
      echo "Error: could not retrieve simulation results library name." >&2
      exit 202
    fi
    if $is_afn; then
      mf_results_preset="$(awk -v mode="$preset_check" -v preset="$preset" -f "$script_dir/get_simPreset_mfrFile.awk" "$building")"
      if [ "X$mf_results_preset" == "X" ]; then
        echo "Error: could not retrieve mass flow results library name." >&2
        exit 202
      fi
    fi
    if $is_CFD; then
      cfd_results_preset="$(awk -v mode="$preset_check" -v preset="$preset" -f "$script_dir/get_simPreset_dfrFile.awk" "$building")"
      if [ "$cfd_results_preset" == "error" ] || [ "X$cfd_results_preset" == "X" ]; then
        echo "Error: invalid simulation preset - old format." >&2
        exit 202
      fi
      cfd_period_preset="$(awk -v mode="$preset_check" -v preset="$preset" -f "$script_dir/get_simPreset_dfrPeriod.awk" "$building")"
      if [ "$cfd_period_preset" == "error" ]; then
        echo "Error: invalid simulation preset - old format." >&2
        exit 202
      fi
    fi
    period="$(awk -v mode="$preset_check" -v preset="$preset" -f "$script_dir/get_simPreset_period.awk" "$building")"
    start="$(expr "$period" : '\([0-9]* [0-9]* \)')"
    start="${start:0:-1}"
    finish="$(expr "$period" : '.*\( [0-9]* [0-9]*\)')"
    finish="${finish:1}"
    timesteps="$(awk -v mode="$preset_check" -v preset="$preset" -f "$script_dir/get_simPreset_timesteps.awk" "$building")"
    startup="$(awk -v mode="$preset_check" -v preset="$preset" -f "$script_dir/get_simPreset_startup.awk" "$building")"

# Check startup is at least 3 days.
    if [ "$startup" -lt 3 ]; then
      echo "Error: invalid simulation preset - startup is less than 3 days." >&2
      exit 202
    fi
  fi

# If running with a simulation preset, and not in the cfg directory,
# bps will place the results libraries in your home directory.
  sim_results_preset=~/"$(basename "$sim_results_preset")"

# This is not true of the mass flow results library.
#  if $is_afn; then mf_results_preset=~/"$(basename "$mf_results_preset")"; fi
  if $is_CFD; then cfd_results_preset=~/"$(basename "$cfd_results_preset")"; fi
fi

# Check for uncertainties definitions.
ucn="$(awk -f "$common_dir/esp-query/processOutput_getUncertaintiesFile.awk" "$tmp_dir/query_results.txt")"
if [ "X$ucn" == "X" ]; then
  is_ucn=false
else
  is_ucn=true
fi

# Set results library names.
sim_results="${results_file}.res"
if $is_afn; then mf_results="${results_file}.mfr"; fi
if $is_CFD; then cfd_results="${results_file}.dfr"; fi




# *** SIMULATE ***

# Set up paths.
if [ "X$up_one" == "X" ]; then
  building_tmp="$building"
  building_dir_tmp="$building_dir"
  tmp_dir_tmp="$tmp_dir"
  sim_results_tmp="$sim_results"
  mf_results_tmp="$mf_results"
  cfd_results_tmp="$cfd_results"
else
  cd ..
  building_tmp="$up_one/$building"
  building_dir_tmp="$(dirname "$building_tmp")"
  tmp_dir_tmp="$up_one/$tmp_dir"
  sim_results_tmp="$up_one/$sim_results"
  mf_results_tmp="$up_one/$mf_results"
  cfd_results_tmp="$up_one/$cfd_results"
fi

if $do_simulation; then

  # Update progress file.
  echo '3' > "$tmp_dir_tmp/progress.txt"

  # Make sure there is no existing results library or ACC-actions file. 
  # Suppress output in case there isn't to prevent chatter.
  rm -f "$sim_results_tmp" > /dev/null
  if $is_afn; then rm -f "$mf_results_tmp" > /dev/null; fi
  if $is_CFD; then rm -f "$cfd_results_tmp" > /dev/null; fi
  rm -f "$building_dir_tmp"/ACC-actions_*.rec > /dev/null
  rm -f "$building_dir_tmp"/cfd3dascii_* > /dev/null

  if $verbose; then
    echo
    echo " Model: $building"
    echo " Simulation results: $results_file"
    echo " Report: $report_final"
    echo " JSON file: $JSON"
    if [ "X$preset" = "X" ]; then
      echo " Analysis period from $start to $finish with $timesteps timesteps per hour"
    else
      echo " Analysis defined by simulation preset \"$preset\""
    fi
    echo
    echo " Simulation commencing, please wait ....."
    echo
  fi

  # Run simulation.
  if ! [ "X$preset" == "X" ]; then
    bps_script=""
    if $is_CFD; then 
      bps -mode script -file "$building_tmp" -p "$preset" silent > "$tmp_dir_tmp/bps.out" <<~

~
    else
      bps -mode script -file "$building_tmp" -p "$preset" silent > "$tmp_dir_tmp/bps.out"
    fi

    mv "$sim_results_preset" "$sim_results_tmp"
    if $is_afn; then
      mv "$mf_results_preset" "$mf_results_tmp"
    fi
    if $is_CFD; then
      mv "$cfd_results_preset" "$cfd_results_tmp"
    fi
  else

    # Update simulation year in cfg file.
    sed -i -e 's/\*year *[0-9]*/*year '"$year"'/' "$building_tmp"
    bps_script="
c
${sim_results_tmp}"
    if $is_afn; then
      bps_script="$bps_script
${mf_results_tmp}"
    fi
    if $is_CFD; then
      bps_script="$bps_script
${cfd_results_tmp}"
    fi
    bps_script="$bps_script
${start}
${finish}
${startup}
${timesteps}"
    if [ "$timesteps" -gt 1 ]; then
      bps_script="$bps_script
n"
    fi
    if $is_CFD; then
  # Run CFD for whole period.
      bps_script="$bps_script
y
${start}
${finish}
${CFD_start_hour}
${CFD_finish_hour}"

  # # Disable CFD for the initial simulation.
  #     bps_script="$bps_script
  # n"
    fi
    bps_script="$bps_script
s
y"
    if $is_ucn; then
      bps_script="$bps_script
d
-"
    fi
    bps_script="$bps_script
PAM simulation
y
y
-
-
"

    echo "$bps_script" > "$tmp_dir_tmp/bps_script.trace"

    bps -mode script -file "$building_tmp" > "$tmp_dir_tmp/bps.out" <<~
${bps_script}
~
  fi

  if ! [ "X$up_one" == "X" ]; then
    cd "$up_one" || exit 1
  fi

  # Check error code and existence of results libraries.
  if [ "$?" -ne 0 ]; then
    echo "Error: simulation failed, please check model manually." >&2
    exit 104
  fi

  if ! [ -f "$sim_results" ]; then
    echo "Error: simulation failed, please check model manually." >&2
    exit 104
  fi

  if $is_afn && ! [ -f "$mf_results" ]; then
    echo "Error: simulation failed, please check model manually." >&2
    exit 104
  fi

  if $is_CFD && ! [ -f "$cfd_results" ]; then
    echo "Error: simulation failed, please check model manually." >&2
    exit 104
  fi

fi



# *** EXTRACT RESULTS ***

# Update progress file.
echo '4' > "$tmp_dir/progress.txt"

# Run res to get occupied hours.
if ! [ "X$up_one" == "X" ]; then
  cd .. || exit 1
fi

res -mode script -file "$sim_results_tmp" > "$tmp_dir_tmp/res.out" <<~

d
c
>
b
${tmp_dir_tmp}/occupied_hours
j
d
-
0.001
>
-
-
-
~

# Check error code and existence of output.
if [ "$?" -ne 0 ] || ! [ -f "$tmp_dir_tmp/occupied_hours" ]; then
  echo "Error: occupancy results extraction failed." >&2
  exit 105
fi

# Extract data from res output.
ocup="$(awk -f "$script_dir/get_occupiedHoursLatex.awk" "$tmp_dir_tmp/occupied_hours")"

# Check data for occupancy.
count=0
ind=0
is_occ=false
for a in $ocup; do
  ((count++))
  if [ $count -eq 1 ]; then
    zone_num="${a:0:-1}"
    if $verbose; then echo " Checking zone $zone_num."; fi
  elif [ $count -eq 4 ]; then 
    if $verbose; then echo " Occupied hours = $a"; fi
    if [ "${a/.}" -gt 0 ] && [ "${array_MRT_sensors[ind]}" -gt 0 ]; then
      if $verbose; then echo " Occupied."; fi
      if ! $is_occ; then is_occ=true; fi
    else
      if $verbose; then echo " Not occupied."; fi
    fi
  elif [ $count -eq 7 ]; then 
    count=0
    ((ind++))
  fi
done

if ! $is_occ; then
# No occupancy, exit with an error.
  echo "Error: no occupancy detected in this model." >&2
  exit 106
fi

# Assess seasons that are covered by the simulation period.
start_day="${start% *}"
start_month="${start#* }"
finish_day="${finish% *}"
finish_month="${finish#* }"
early_winter=false
#EWS='1 1'
EWF='28 2'
spring=false
SpS='1 3'
SpF='31 5'
summer=false
SuS='1 6'
SuF='31 8'
autumn=false
AS='1 9'
AF='30 11'
late_winter=false
LWS='1 12'
#LWF='31 12'
if [ "$start_month" -le "${EWF#* }" ]; then 
  early_winter=true
  early_winter_start="$start"
  if [ "$finish_month" -ge "${LWS#* }" ]; then
    early_winter_finish="$EWF"
    spring=true
    spring_start="$SpS"
    spring_finish="$SpF"
    summer=true
    summer_start="$SuS"
    summer_finish="$SuF"
    autumn=true
    autumn_start="$AS"
    autumn_finish="$AF"
    late_winter=true
    late_winter_start="$LWS"
    late_winter_finish="$finish"
  elif [ "$finish_month" -ge ${AS#* } ]; then
    early_winter_finish="$EWF"
    spring=true
    spring_start="$SpS"
    spring_finish="$SpF"
    summer=true
    summer_start="$SuS"
    summer_finish="$SuF"
    autumn=true
    autumn_start="$AS"
    autumn_finish="$finish"
  elif [ "$finish_month" -ge ${SuS#* } ]; then
    early_winter_finish="$EWF"
    spring=true
    spring_start="$SpS"
    spring_finish="$SpF"
    summer=true
    summer_start="$SuS"
    summer_finish="$finish"
  elif [ "$finish_month" -ge ${SpS#* } ]; then
    early_winter_finish="$EWF"
    spring=true
    spring_start="$SpS"
    spring_finish="$finish"
  else
    early_winter_finish="$finish"
  fi
elif [ "$start_month" -le ${SpF#* } ]; then 
  spring=true
  spring_start="$start"
  if [ "$finish_month" -ge ${LWS#* } ]; then
    spring_finish="$SpF"
    summer=true
    summer_start="$SuS"
    summer_finish="$SuF"
    autumn=true
    autumn_start="$AS"
    autumn_finish="$AF"
    late_winter=true
    late_winter_start="$LWS"
    late_winter_finish="$finish"
  elif [ "$finish_month" -ge ${AS#* } ]; then
    spring_finish="$SpF"
    summer=true
    summer_start="$SuS"
    summer_finish="$SuF"
    autumn=true
    autumn_start="$AS"
    autumn_finish="$finish"
  elif [ "$finish_month" -ge ${SuS#* } ]; then
    spring_finish="$SpF"
    summer=true
    summer_start="$SuS"
    summer_finish="$finish"
  else
    spring_finish="$finish"
  fi
elif [ "$start_month" -le ${SuF#* } ]; then 
  summer=true
  summer_start="$start"
  if [ "$finish_month" -ge ${LWS#* } ]; then
    summer_finish="$SuF"
    autumn=true
    autumn_start="$AS"
    autumn_finish="$AF"
    late_winter=true
    late_winter_start="$LWS"
    late_winter_finish="$finish"
  elif [ "$finish_month" -ge ${AS#* } ]; then
    summer_finish="$SuF"
    autumn=true
    autumn_start="$AS"
    autumn_finish="$finish"
  else
    summer_finish="$finish"
  fi
elif [ "$start_month" -le ${AF#* } ]; then 
  autumn=true
  autumn_start="$start"
  if [ "$finish_month" -ge ${LWS#* } ]; then
    autumn_finish="$AF"
    late_winter=true
    late_winter_start="$LWS"
    late_winter_finish="$finish"
  else
    autumn_finish="$finish"
  fi
else
  late_winter=true
  late_winter_start="$start"
  late_winter_finish="$finish"
fi

# Define res commands.

# Open CFD library first to avoid unexpected prompts.
if $is_CFD; then
  res_script="
h
${cfd_results_tmp}"
  if [ "$CFDdomain_count" -gt 1 ]; then
    res_script="$res_script
1"
  fi
  res_script="$res_script
-"
fi

# Get operative temperature for each season encompassed by the simulation period.

first_season=true
if "$early_winter"; then

  num_extra_opt_files=0

# Period
  res_script="$res_script
c
g
*
a
3
$early_winter_start 1
$early_winter_finish 24
$timesteps"
  if [ "$timesteps" -gt 1 ]; then
    res_script="$res_script
y"
  fi

  num_extra_opt_files=0

# Only need to activate filtering once; will stay on for the rest of results.
  if $first_season; then
    res_script="$res_script
+
b
>
b
$tmp_dir_tmp/early_winter_opt

"
    first_season=false
  fi
  first=true
  num_cols=0
  for i1 in "${array_zones_with_MRTsensors[@]}"; do
    i0=$((i1-1))
    if [ "$number_zones" -gt 1 ]; then
      res_script="$res_script
4
<
1
$i1"
    fi
    res_script="$res_script
b
m
-"
    res_script="$res_script
*
-"
    if [ "${array_CFD_domains[i0]}" -lt 2 ]; then
      res_script="$res_script
y"
    fi
    ((num_cols+=array_MRT_sensors[i0]))
    if [ "$num_cols" -eq 41 ]; then
      ((num_extra_opt_files++))
      res_script="$res_script
!
>
>
b
${tmp_dir_tmp}/early_winter_opt_${num_extra_opt_files}

"
      num_cols=0
    fi
  done
  res_script="$res_script
!
>
-
-"

# summary stats
  res_script="$res_script
d
a"
  for i1 in "${array_zones_with_MRTsensors[@]}"; do
    i0=$((i1-1))
    if [ "$number_zones" -gt 1 ]; then
      res_script="$res_script
4
<
1
$i1"
    fi
    i0_pad="$(printf "%02d" $i0)"
    res_script="$res_script
>
b
${tmp_dir_tmp}/early_winter_opt_summary_${i0_pad}
b
m
-"
    res_script="$res_script
*
-"
    if [ "${array_CFD_domains[i0]}" -lt 2 ]; then
      res_script="$res_script
y"
    fi
    res_script="$res_script
>"
  done
  res_script="$res_script
-
-"
fi



if "$spring"; then

  num_extra_opt_files=0

# Period
  res_script="$res_script
c
g
*
a
3
$spring_start 1
$spring_finish 24
$timesteps"
  if [ "$timesteps" -gt 1 ]; then
    res_script="$res_script
y"
  fi

  num_extra_opt_files=0

# Only need to activate filtering once; will stay on for the rest of results.
  if $first_season; then
    res_script="$res_script
+
b"
    first_season=false
  fi

  res_script="$res_script
>
b
$tmp_dir_tmp/spring_opt

"
  first=true
  num_cols=0
  for i1 in "${array_zones_with_MRTsensors[@]}"; do
    i0=$((i1-1))
    if [ "$number_zones" -gt 1 ]; then
      res_script="$res_script
4
<
1
$i1"
    fi
    res_script="$res_script
b
m
-"
    res_script="$res_script
*
-"
    if [ "${array_CFD_domains[i0]}" -lt 2 ]; then
      res_script="$res_script
y"
    fi
    ((num_cols+=array_MRT_sensors[i0]))
    if [ "$num_cols" -eq 41 ]; then
      ((num_extra_opt_files++))
      res_script="$res_script
!
>
>
b
${tmp_dir_tmp}/spring_opt_${num_extra_opt_files}

"
      num_cols=0
    fi
  done
  res_script="$res_script
!
>
-
-"

# summary stats
  res_script="$res_script
d
a"
  for i1 in "${array_zones_with_MRTsensors[@]}"; do
    i0=$((i1-1))
    if [ "$number_zones" -gt 1 ]; then
      res_script="$res_script
4
<
1
$i1"
    fi
    i0_pad="$(printf "%02d" $i0)"
    res_script="$res_script
>
b
${tmp_dir_tmp}/spring_opt_summary_${i0_pad}
b
m
-"
    res_script="$res_script
*
-"
    if [ "${array_CFD_domains[i0]}" -lt 2 ]; then
      res_script="$res_script
y"
    fi
    res_script="$res_script
>"
  done
  res_script="$res_script
-
-"
fi



if "$summer"; then

  num_extra_opt_files=0

# Period
  res_script="$res_script
c
g
*
a
3
$summer_start 1
$summer_finish 24
$timesteps"
  if [ "$timesteps" -gt 1 ]; then
    res_script="$res_script
y"
  fi

# Only need to activate filtering once; will stay on for the rest of results.
  if $first_season; then
    res_script="$res_script
+
b"
    first_season=false
  fi

  num_extra_opt_files=0

  res_script="$res_script
>
b
$tmp_dir_tmp/summer_opt

"
  first=true
  num_cols=0
  for i1 in "${array_zones_with_MRTsensors[@]}"; do
    i0=$((i1-1))
    if [ "$number_zones" -gt 1 ]; then
      res_script="$res_script
4
<
1
$i1"
    fi
    res_script="$res_script
b
m
-"
    res_script="$res_script
*
-"
    if [ "${array_CFD_domains[i0]}" -lt 2 ]; then
      res_script="$res_script
y"
    fi
    ((num_cols+=array_MRT_sensors[i0]))
    if [ "$num_cols" -eq 41 ]; then
      ((num_extra_opt_files++))
      res_script="$res_script
!
>
>
b
${tmp_dir_tmp}/summer_opt_${num_extra_opt_files}

"
      num_cols=0
    fi
  done
  res_script="$res_script
!
>
-
-"

# summary stats
  res_script="$res_script
d
a"
  for i1 in "${array_zones_with_MRTsensors[@]}"; do
    i0=$((i1-1))
    if [ "$number_zones" -gt 1 ]; then
      res_script="$res_script
4
<
1
$i1"
    fi
    i0_pad="$(printf "%02d" $i0)"
    res_script="$res_script
>
b
${tmp_dir_tmp}/summer_opt_summary_${i0_pad}
b
m
-"
    res_script="$res_script
*
-"
    if [ "${array_CFD_domains[i0]}" -lt 2 ]; then
      res_script="$res_script
y"
    fi
    res_script="$res_script
>"
  done
  res_script="$res_script
-
-"
fi




if "$autumn"; then

  num_extra_opt_files=0

# Period
  res_script="$res_script
c
g
*
a
3
$autumn_start 1
$autumn_finish 24
$timesteps"
  if [ "$timesteps" -gt 1 ]; then
    res_script="$res_script
y"
  fi

  num_extra_opt_files=0

# Only need to activate filtering once; will stay on for the rest of results.
  if $first_season; then
    res_script="$res_script
+
b"
    first_season=false
  fi

  res_script="$res_script
>
b
$tmp_dir_tmp/autumn_opt

"
  first=true
  num_cols=0
  for i1 in "${array_zones_with_MRTsensors[@]}"; do
    i0=$((i1-1))
    if [ "$number_zones" -gt 1 ]; then
      res_script="$res_script
4
<
1
$i1"
    fi
    res_script="$res_script
b
m
-"
    res_script="$res_script
*
-"
    if [ "${array_CFD_domains[i0]}" -lt 2 ]; then
      res_script="$res_script
y"
    fi
    ((num_cols+=array_MRT_sensors[i0]))
    if [ "$num_cols" -eq 41 ]; then
      ((num_extra_opt_files++))
      res_script="$res_script
!
>
>
b
${tmp_dir_tmp}/autumn_opt_${num_extra_opt_files}

"
      num_cols=0
    fi
  done
  res_script="$res_script
!
>
-
-"

# summary stats
  res_script="$res_script
d
a"
  for i1 in "${array_zones_with_MRTsensors[@]}"; do
    i0=$((i1-1))
    if [ "$number_zones" -gt 1 ]; then
      res_script="$res_script
4
<
1
$i1"
    fi
    i0_pad="$(printf "%02d" $i0)"
    res_script="$res_script
>
b
${tmp_dir_tmp}/autumn_opt_summary_${i0_pad}
b
m
-"
    res_script="$res_script
*
-"
    if [ "${array_CFD_domains[i0]}" -lt 2 ]; then
      res_script="$res_script
y"
    fi
    res_script="$res_script
>"
  done
  res_script="$res_script
-
-"
fi





if "$late_winter"; then

  num_extra_opt_files=0

# Period
  res_script="$res_script
c
g
*
a
3
$late_winter_start 1
$late_winter_finish 24
$timesteps"
  if [ "$timesteps" -gt 1 ]; then
    res_script="$res_script
y"
  fi

  num_extra_opt_files=0

# Only need to activate filtering once; will stay on for the rest of results.
  if $first_season; then
    res_script="$res_script
+
b"
    first_season=false
  fi

  res_script="$res_script
>
b
${tmp_dir_tmp}/late_winter_opt

"
  first=true
  num_cols=0
  for i1 in "${array_zones_with_MRTsensors[@]}"; do
    i0=$((i1-1))
    if [ "$number_zones" -gt 1 ]; then
      res_script="$res_script
4
<
1
$i1"
    fi
    res_script="$res_script
b
m
-"
    res_script="$res_script
*
-"
    if [ "${array_CFD_domains[i0]}" -lt 2 ]; then
      res_script="$res_script
y"
    fi
    ((num_cols+=array_MRT_sensors[i0]))
    if [ "$num_cols" -eq 41 ]; then
        ((num_extra_opt_files++))
        res_script="$res_script
!
>
>
b
${tmp_dir_tmp}/late_winter_opt_${num_extra_opt_files}

"
      num_cols=0
    fi
  done
  res_script="$res_script
!
>
-
-"

# summary stats
  res_script="$res_script
d
a"
  for i1 in "${array_zones_with_MRTsensors[@]}"; do
    i0=$((i1-1))
    if [ "$number_zones" -gt 1 ]; then
      res_script="$res_script
4
<
1
$i1"
    fi
    i0_pad="$(printf "%02d" $i0)"
    res_script="$res_script
>
b
${tmp_dir_tmp}/late_winter_opt_summary_${i0_pad}
b
m
-"
    res_script="$res_script
*
-"
    if [ "${array_CFD_domains[i0]}" -lt 2 ]; then
      res_script="$res_script
y"
    fi
    res_script="$res_script
>"
  done
  res_script="$res_script
-
-"
fi


# Now get floor temperature discomfort.
res_script="$res_script
3
$start 1
$finish 24
$timesteps"
if [ "$timesteps" -gt 1 ]; then
  res_script="$res_script
y"
fi
res_script="$res_script
c
g
*
a"
for i0 in "${array_zone_indices[@]}"; do
  i1=$((i0+1))

  # Get floor surface numbers for this zone.
  # While we're here, construct array of number of zone floor surfaces.
  if [ "${array_MRT_sensors[i0]}" -eq 0 ]; then

    # For zones without MRT sensors, we put a 0 in the floor surfaces array.
    # Logic below ensures that the floor PTD array inherits "not occupied" entries for such zones.
    array_num_floor_surfaces[i0]=0

  elif [ "${array_MRT_sensors[i0]}" -gt 0 ]; then
    floor_surfaces="$(awk -v zone="$i1" -f "$common_dir/esp-query/processOutput_getSingleZoneSpaceSeparatedFloorSurfs.awk" "$tmp_dir_tmp/query_results.txt")"
    if [ $? -ne 0 ]; then
      echo "Error: unable to find floor surface(s) for occupied zone ${i1}" >&2
      exit $((300+$i1))
    fi
    array_floor_surfaces=($floor_surfaces)
    num_floor_surfaces="${#array_floor_surfaces[@]}"
    if [ "${num_floor_surfaces}" -eq 1 ]; then
      if [ "${array_floor_surfaces[0]}" -eq 0 ]; then
        num_floor_surfaces=0
      fi
    fi
    array_num_floor_surfaces[i0]="$num_floor_surfaces"
    if [ "${num_floor_surfaces}" -eq 0 ]; then 
      echo "Error: no floor surfaces defined for occupied zone ${i1}" >&2
      exit $((300+$i1))
    fi

    i1_pad="$(printf "%02d" $i1)"
    res_script="$res_script
4
<
1
${i1}
>
b
${tmp_dir_tmp}/floor_discomfort_${i1_pad}

c
e
<
${num_floor_surfaces}"
    for j in "${array_floor_surfaces[@]}"; do
      res_script="$res_script
${j}"
    done
    res_script="$res_script
!
>"
  fi
done
res_script="$res_script
-
-"

# Summary stats.
  res_script="$res_script
d
a"
for i1 in "${array_zones_with_MRTsensors[@]}"; do
  i0=$((i1-1))

# Get floor surface numbers for this zone.
  floor_surfaces="$(awk -v zone="$i1" -f "$common_dir/esp-query/processOutput_getSingleZoneSpaceSeparatedFloorSurfs.awk" "$tmp_dir_tmp/query_results.txt")"
  if [ $? -ne 0 ]; then
    echo "Error: unable to find floor surface(s) for occupied zone ${i1}" >&2
    exit $((300+$i1))
  fi
  array_floor_surfaces=($floor_surfaces)
  num_floor_surfaces="${array_num_floor_surfaces[i0]}"

  i0_pad="$(printf "%02d" $i0)"
  res_script="$res_script
4
<
1
${i1}
>
b
${tmp_dir_tmp}/floor_summary_${i0_pad}
c
e
<
${num_floor_surfaces}"
  for j in "${array_floor_surfaces[@]}"; do
    res_script="$res_script
${j}"
  done
  res_script="$res_script
>"
done
res_script="$res_script
-
-"


# Now get ceiling radiant asymmetry discomfort.
num_extra_ceiling_files=0

res_script="$res_script
c
g
*
a
>
b
$tmp_dir_tmp/ceiling_discomfort
"
if [ "$number_zones_with_MRTsensors" -gt 1 ]; then
  if [ "$number_MRT_sensors" -gt 41 ]; then
    num_sensors_left="$number_MRT_sensors"
    num_zones_left="$number_zones"
    cur_zone=1
    num_zones_tmp=0
    num_sensors_from_previous=0
    while [ "$num_sensors_left" -gt 41 ]; do
      first=true
      num_cols_left=41
      s=""
      if [ "$num_sensors_from_previous" -gt 0 ]; then
        already_done_zone=true
      else
        already_done_zone=false
      fi
      while [ "$num_cols_left" -gt 0 ]; do
        zon_num_sensors="${array_MRT_sensors[cur_zone-1]}"
        num_sensors_tmp="$((zon_num_sensors-num_sensors_from_previous))"
        if [ "$num_sensors_tmp" -le "$num_cols_left" ]; then
          ((num_zones_tmp++))
          if $first; then
            ((num_cols_left-=num_sensors_tmp))
            first=false
          else
            ((num_cols_left-=zon_num_sensors))
          fi
          s="$s
$((cur_zone))"
          ((cur_zone++))
        else
          if $first; then
            ((i_st+=41))
            ((num_sensors_from_previous+=41))
            first=false
          else
            i_st=$((1+num_sensors_from_previous))
            num_sensors_from_previous=$((num_cols_left))
          fi
          i_end=$((i_st+40))
          ((num_zones_tmp++))
          num_cols_left=0
          s="$s
$((cur_zone))"
        fi
      done
      ((num_extra_ceiling_files++))
      res_script="$res_script
4
<
$num_zones_tmp$s"
      res_script="$res_script
c
f
<
41"
      ii=$i_st
      while [ "$ii" -le "$i_end" ]; do
        res_script="$res_script
${ii}"
      done
      res_script="$res_script
!
>
>
b
$tmp_dir_tmp/ceiling_discomfort_$num_extra_ceiling_files
"
      ((num_zones_left-=num_zones_tmp))
      if $already_done_zone; then 
        ((num_zones_left+=1))
      fi
      ((num_sensors_left-=41))
    done
    res_script="$res_script
4
<
$num_zones_left"
    i="$cur_zone"
    while [ "$i" -le "$number_zones" ]; do
      res_script="$res_script
${i}"
      ((i++))
    done
    res_script="$res_script
c
f
<
${num_sensors_left}"
    i=0
    ii="$((num_sensors_from_previous+1))"
    while [ "$i" -lt "$num_sensors_left" ]; do
      res_script="$res_script
${ii}"
      ((i++))
      ((ii++))
    done
  else
    res_script="$res_script
4
*
-
c
f
*
-"
  fi
else
  res_script="$res_script
c
f
*
-"
fi
res_script="$res_script
!
>
-
-"

# Summary stats.
res_script="$res_script
d
a"
for i1 in "${array_zones_with_MRTsensors[@]}"; do
  i0=$((i1-1))
  i0_pad="$(printf "%02d" $i0)"
  res_script="$res_script
4
<
1
${i1}
>
b
${tmp_dir_tmp}/ceiling_summary_${i0_pad}
c
f
*
-
>"
done
res_script="$res_script
-
-"


# Now get wall radiant asymmetry discomfort,.
res_script="$res_script
c
g
*
a"
if [ "$number_zones" -gt 1 ]; then
  for i in "${array_zone_indices[@]}"; do
    if [ "${array_MRT_sensors[i]}" -gt 0 ]; then
      zone_ind=$((i+1))
      zi_pad="$(printf "%02d" $zone_ind)"
      res_script="$res_script
4
<
1
${zone_ind}"
      num_MRT_sensors="${array_MRT_sensors[i]}"
      j=1
      while [ "$j" -le "$num_MRT_sensors" ]; do
        si_pad="$(printf "%02d" $j)"
        res_script="$res_script
>
b
$tmp_dir_tmp/wall_discomfort_${zi_pad}_${si_pad}

c
g
a
<
1
${j}
c
g
b
<
1
${j}
c
g
c
<
1
${j}
c
g
e
<
1
${j}
!
>"
        ((j++))
      done
    fi
  done
else

  num_MRT_sensors="${array_MRT_sensors[i]}"
  j=1
  while [ "$j" -le "$num_MRT_sensors" ]; do
    si_pad="$(printf "%02d" $j)"
    res_script="$res_script
>
b
$tmp_dir_tmp/wall_discomfort_${si_pad}

c
g
a
<
1
${j}
c
g
b
<
1
${j}
c
g
c
<
1
${j}
c
g
e
<
1
${j}
!
>"
    ((j++))
  done
fi
res_script="$res_script
-
-"

# Summary stats.
res_script="$res_script
d
a"
for i1 in "${array_zones_with_MRTsensors[@]}"; do
  i0=$((i1-1))
  i0_pad="$(printf "%02d" $i0)"
  res_script="$res_script
4
<
1
${i1}
>
b
${tmp_dir_tmp}/wall_summary_${i0_pad}_1
c
g
a
*
-
>
>
b
${tmp_dir_tmp}/wall_summary_${i0_pad}_2
c
g
b
*
-
>
>
b
${tmp_dir_tmp}/wall_summary_${i0_pad}_3
c
g
c
*
-
>
>
b
${tmp_dir_tmp}/wall_summary_${i0_pad}_4
c
g
e
*
-
>"
done
res_script="$res_script
-
-"


# Now get head to foot dT discomfort, if there is CFD.
num_extra_vertdT_files=0

if $is_CFDandMRT; then

  res_script="$res_script
c
g
*
a
>
b
$tmp_dir_tmp/vertdT_discomfort
"
  if [ "$number_zones" -gt 1 ]; then
    if [ "$number_MRT_sensors" -gt 41 ]; then
      num_sensors_left="$number_MRT_sensors"
      num_zones_left="$number_zones"
      cur_zone=1
      num_zones_tmp=0
      num_sensors_from_previous=0
      while [ "$num_sensors_left" -gt 41 ]; do
        first=true
        num_cols_left=41
        s=""
        if [ "$num_sensors_from_previous" -gt 0 ]; then
          already_done_zone=true
        else
          already_done_zone=false
        fi
        while [ "$num_cols_left" -gt 0 ]; do
          zon_num_sensors="${array_MRT_sensors[cur_zone-1]}"
          num_sensors_tmp="$((zon_num_sensors-num_sensors_from_previous))"
          if [ "$num_sensors_tmp" -le "$num_cols_left" ]; then
            ((num_zones_tmp++))
            if $first; then
              ((num_cols_left-=num_sensors_tmp))
              first=false
            else
              ((num_cols_left-=zon_num_sensors))
            fi
            s="$s
$((cur_zone))"
            ((cur_zone++))
          else
            if $first; then
              ((i_st+=41))
              ((num_sensors_from_previous+=41))
              first=false
            else
              i_st=$((1+num_sensors_from_previous))
              num_sensors_from_previous=$((num_cols_left))
            fi
            i_end=$((i_st+40))
            ((num_zones_tmp++))
            num_cols_left=0
            s="$s
$((cur_zone))"
          fi
        done
        ((num_extra_vertdT_files++))
        res_script="$res_script
4
<
$num_zones_tmp$s"
        res_script="$res_script
c
d
<
41"
        ii=$i_st
        while [ "$ii" -le "$i_end" ]; do
          res_script="$res_script
${ii}"
        done
        res_script="$res_script
!
>
>
b
$tmp_dir_tmp/vertdT_discomfort_$num_extra_vertdT_files
"
        ((num_zones_left-=num_zones_tmp))
        if $already_done_zone; then 
          ((num_zones_left+=1))
        fi
        ((num_sensors_left-=41))
      done
      res_script="$res_script
4
<
$num_zones_left"
      i="$cur_zone"
      while [ "$i" -le "$number_zones" ]; do
        res_script="$res_script
${i}"
        ((i++))
      done
      res_script="$res_script
c
d
<
${num_sensors_left}"
      i=0
      ii="$((num_sensors_from_previous+1))"
      while [ "$i" -lt "$num_sensors_left" ]; do
        res_script="$res_script
${ii}"
        ((i++))
        ((ii++))
      done

    else
      res_script="$res_script
4
*
-
c
d
<"
      num_sensors=0
      for i1 in "${array_zones_with_CFDandMRT[@]}"; do
        i0=$((i1-1))
        num_sensors=$((num_sensors+array_MRT_sensors[i0]))
      done
      res_script="$res_script
${num_sensors}"
      for i1z in "${array_zones_with_CFDandMRT[@]}"; do
        for i0s in "${array_sensor_indices[@]}"; do
          if [ "${array_sensor_zones[i0s]}" -eq "$i1z" ]; then
            i1s=$((i0s+1))
            res_script="$res_script
${i1s}"
          fi
        done
      done
    fi
  else
    res_script="$res_script
c
d
*
-"
  fi
  res_script="$res_script
!
>
-
-"

# Summary stats.
  res_script="$res_script
d
a"
  for i1 in "${array_zones_with_CFDandMRT[@]}"; do
    i0=$((i1-1))
    i0_pad="$(printf "%02d" $i0)"
    res_script="$res_script
4
<
1
${i1}
>
b
${tmp_dir_tmp}/vertdT_summary_${i0_pad}
c
d
*
-
>"
  done
  res_script="$res_script
-
-"

fi


# Now get draught discomfort, if there are MRT sensors and CFD.
num_extra_draught_files=0

if $is_CFDandMRT; then

  res_script="$res_script
c
g
*
a
>
b
$tmp_dir_tmp/draught_discomfort
"
  if [ "$number_zones" -gt 1 ]; then
    if [ "$number_MRT_sensors" -gt 41 ]; then
      num_sensors_left="$number_MRT_sensors"
      num_zones_left="$number_zones"
      cur_zone=1
      num_zones_tmp=0
      num_sensors_from_previous=0
      while [ "$num_sensors_left" -gt 41 ]; do
        first=true
        num_cols_left=41
        s=""
        if [ "$num_sensors_from_previous" -gt 0 ]; then
          already_done_zone=true
        else
          already_done_zone=false
        fi
        while [ "$num_cols_left" -gt 0 ]; do
          zon_num_sensors="${array_MRT_sensors[cur_zone-1]}"
          num_sensors_tmp="$((zon_num_sensors-num_sensors_from_previous))"
          if [ "$num_sensors_tmp" -le "$num_cols_left" ]; then
            ((num_zones_tmp++))
            if $first; then
              ((num_cols_left-=num_sensors_tmp))
              first=false
            else
              ((num_cols_left-=zon_num_sensors))
            fi
            s="$s
$((cur_zone))"
            ((cur_zone++))
          else
            if $first; then
              ((i_st+=41))
              ((num_sensors_from_previous+=41))
              first=false
            else
              i_st=$((1+num_sensors_from_previous))
              num_sensors_from_previous=$((num_cols_left))
            fi
            i_end=$((i_st+40))
            ((num_zones_tmp++))
            num_cols_left=0
            s="$s
$((cur_zone))"
          fi
        done
        ((num_extra_draught_files++))
        res_script="$res_script
4
<
$num_zones_tmp$s"
        res_script="$res_script
c
h
<
41"
        ii=$i_st
        while [ "$ii" -le "$i_end" ]; do
          res_script="$res_script
${ii}"
        done
        res_script="$res_script
!
>
>
b
$tmp_dir_tmp/draught_discomfort_$num_extra_draught_files
"
        ((num_zones_left-=num_zones_tmp))
        if $already_done_zone; then 
          ((num_zones_left+=1))
        fi
        ((num_sensors_left-=41))
      done
      res_script="$res_script
4
<
$num_zones_left"
      i="$cur_zone"
      while [ "$i" -le "$number_zones" ]; do
        res_script="$res_script
${i}"
        ((i++))
      done
      res_script="$res_script
c
h
<
${num_sensors_left}"
      i=0
      ii="$((num_sensors_from_previous+1))"
      while [ "$i" -lt "$num_sensors_left" ]; do
        res_script="$res_script
${ii}"
        ((i++))
        ((ii++))
      done

    else
      res_script="$res_script
4
*
-
c
h
<"
      num_sensors=0
      for i1 in "${array_zones_with_CFDandMRT[@]}"; do
        i0=$((i1-1))
        num_sensors=$((num_sensors+array_MRT_sensors[i0]))
      done
      res_script="$res_script
${num_sensors}"
      for i1z in "${array_zones_with_CFDandMRT[@]}"; do
        for i0s in "${array_sensor_indices[@]}"; do
          if [ "${array_sensor_zones[i0s]}" -eq "$i1z" ]; then
            i1s=$((i0s+1))
            res_script="$res_script
${i1s}"
          fi
        done
      done
    fi
  else
    res_script="$res_script
c
h
*
-"
  fi
  res_script="$res_script
!
>
-
-"

# Summary stats.
  res_script="$res_script
d
a"
  for i1 in "${array_zones_with_CFDandMRT[@]}"; do
    i0=$((i1-1))
    i0_pad="$(printf "%02d" $i0)"
    res_script="$res_script
4
<
1
${i1}
>
b
${tmp_dir_tmp}/draught_summary_${i0_pad}
c
h
*
-
>"
  done
  res_script="$res_script
-
-"

fi


# Finally, for models with CFD, get air temperature, MRT, air velocity and co2 concentration if available.
if $is_CFDandMRT; then

  for i1_zone in "${array_zones_with_CFDandMRT[@]}"; do  
    i0_zone="$((i1_zone-1))"

    i1_sensor=0
    while [ "$i1_sensor" -lt "${array_MRT_sensors[i0_zone]}" ]; do
      ((i1_sensor++))

      res_script="$res_script
c
g
*
a"

      # Get air temperature and air velocity from CFD results.
      res_script="$res_script
o
>
b
$tmp_dir_tmp/zone${i1_zone}_sensor${i1_sensor}_cfdtimeseries.txt

i
b
<
1
${i1_sensor}
h
b
<
1
${i1_sensor}"

      # If there are contaminants, and CO2 is tracked in this domain,
      # get co2 concentration.
      if $is_1ctm && [[ "$CFD_contam" == *zone#"$i1_zone"=CO2* ]]; then
        res_script="$res_script
k
b
<
1
${i1_sensor}
<
1
1"
      fi

      res_script="$res_script
!
>
-"

      # Get MRT from zone results.
      res_script="$res_script
>
b
$tmp_dir_tmp/zone${i1_zone}_sensor${i1_sensor}_zonetimeseries.txt

4
<
1
${i1_zone}
b
g
-
<
1
${i1_sensor}
!
>
-
-"
    done
  done
fi

res_script="$res_script
-
"

echo "$res_script" > "$tmp_dir_tmp/res_script.trace"

# Run res.
res -mode script -file "$sim_results_tmp" >> "$tmp_dir_tmp/res.out" <<~
${res_script}
~

# Combine op temp summaries.
if $early_winter; then
  x="$(awk -f "$script_dir/combine_summaries.awk" $tmp_dir_tmp/early_winter_opt_summary_*)"
  echo "$x" > "$tmp_dir_tmp/early_winter_opt_summary"
fi
if $spring; then
  x="$(awk -f "$script_dir/combine_summaries.awk" $tmp_dir_tmp/spring_opt_summary_*)"
  echo "$x" > "$tmp_dir_tmp/spring_opt_summary"
fi
if $summer; then
  x="$(awk -f "$script_dir/combine_summaries.awk" $tmp_dir_tmp/summer_opt_summary_*)"
  echo "$x" > "$tmp_dir_tmp/summer_opt_summary"
fi
if $autumn; then
  x="$(awk -f "$script_dir/combine_summaries.awk" $tmp_dir_tmp/autumn_opt_summary_*)"
  echo "$x" > "$tmp_dir_tmp/autumn_opt_summary"
fi
if $late_winter; then
  x="$(awk -f "$script_dir/combine_summaries.awk" $tmp_dir_tmp/late_winter_opt_summary_*)"
  echo "$x" > "$tmp_dir_tmp/late_winter_opt_summary"
fi 
x="$(awk -f "$script_dir/combine_summaries.awk" $tmp_dir_tmp/*_opt_summary_*)"
echo "$x" > "$tmp_dir_tmp/all_opt_summary"

# Combine op temp results if needed.
if [ "$num_extra_opt_files" -gt 0 ]; then  
  if "$early_winter"; then
    x="$(awk -f "$script_dir/combine_columnData.awk" $tmp_dir_tmp/early_winter_opt*)"
    echo "$x" > "$tmp_dir_tmp/early_winter_opt"
  fi
  if "$spring"; then
    x="$(awk -f "$script_dir/combine_columnData.awk" $tmp_dir_tmp/spring_opt*)"
    echo "$x" > "$tmp_dir_tmp/spring_opt"
  fi
  if "$summer"; then
    x="$(awk -f "$script_dir/combine_columnData.awk" $tmp_dir_tmp/summer_opt*)"
    echo "$x" > "$tmp_dir_tmp/summer_opt"
  fi
  if "$autumn"; then
    x="$(awk -f "$script_dir/combine_columnData.awk" $tmp_dir_tmp/autumn_opt*)"
    echo "$x" > "$tmp_dir_tmp/autumn_opt"
  fi
  if "$late_winter"; then
    x="$(awk -f "$script_dir/combine_columnData.awk" $tmp_dir_tmp/late_winter_opt*)"
    echo "$x" > "$tmp_dir_tmp/late_winter_opt"
  fi
fi

# Combine floor discomfort summaries.
x="$(awk -f "$script_dir/combine_summaries.awk" $tmp_dir_tmp/floor_summary_*)"
echo "$x" > "$tmp_dir_tmp/floor_summary"

# Combine floor discomfort results if needed.
#if [ "$number_zones_with_MRTsensors" -gt 1 ]; then
  x="$(awk -f "$script_dir/combine_columnData.awk" $tmp_dir_tmp/floor_discomfort_*)"
  echo "$x" > "$tmp_dir_tmp/floor_discomfort"
#fi

# Combine ceiling discomfort summaries.
x="$(awk -f "$script_dir/combine_summaries.awk" $tmp_dir_tmp/ceiling_summary_*)"
echo "$x" > "$tmp_dir_tmp/ceiling_summary"

# Combine ceiling discomfort results if needed.
if [ "$num_extra_ceiling_files" -gt 0 ]; then
  x="$(awk -f "$script_dir/combine_columnData.awk" $tmp_dir_tmp/ceiling_discomfort*)"
  echo "$x" > "$tmp_dir_tmp/ceiling_discomfort"
fi

# Combine wall discomfort summaries.
x="$(awk -f "$script_dir/combine_summaries.awk" $tmp_dir_tmp/wall_summary_*)"
echo "$x" > "$tmp_dir_tmp/wall_summary"

# Combine wall discomfort results if needed.
# if [ "$number_zones" -gt 1 ]; then
  x="$(awk -f "$script_dir/combine_columnData.awk" $tmp_dir_tmp/wall_discomfort_*)"
  echo "$x" > "$tmp_dir_tmp/wall_discomfort"
# fi

if $is_CFDandMRT; then

# Combine vertdT discomfort summaries.
  x="$(awk -f "$script_dir/combine_summaries.awk" $tmp_dir_tmp/vertdT_summary_*)"
  echo "$x" > "$tmp_dir_tmp/vertdT_summary"

# Combine vertdT discomfort results if needed.
  if [ "$num_extra_vertdT_files" -gt 0 ]; then
    x="$(awk -f "$script_dir/combine_columnData.awk" $tmp_dir_tmp/vertdT_discomfort*)"
    echo "$x" > "$tmp_dir_tmp/vertdT_discomfort"
  fi

# Combine draught discomfort summaries.
  x="$(awk -f "$script_dir/combine_summaries.awk" $tmp_dir_tmp/draught_summary_*)"
  echo "$x" > "$tmp_dir_tmp/draught_summary"

# Combine draught discomfort results if needed.
  if [ "$num_extra_draught_files" -gt 0 ]; then
    x="$(awk -f "$script_dir/combine_columnData.awk" $tmp_dir_tmp/draught_discomfort*)"
    echo "$x" > "$tmp_dir_tmp/draught_discomfort"
  fi
fi

# Check error code and existence of output.
if [ "$?" -ne 0 ]; then
  echo "Error: results extraction failed." >&2
  exit 105
fi

if "$early_winter"; then
  if ! [ -f "$tmp_dir_tmp/early_winter_opt" ] || ! [ -f "$tmp_dir_tmp/early_winter_opt_summary" ]; then
    echo "Error: results extraction failed." >&2
    exit 105
  fi
fi

if "$spring"; then
  if ! [ -f "$tmp_dir_tmp/spring_opt" ] || ! [ -f "$tmp_dir_tmp/spring_opt_summary" ]; then
    echo "Error: results extraction failed." >&2
    exit 105
  fi
fi

if "$summer"; then
  if ! [ -f "$tmp_dir_tmp/summer_opt" ] || ! [ -f "$tmp_dir_tmp/summer_opt_summary" ]; then
    echo "Error: results extraction failed." >&2
    exit 105
  fi
fi

if "$autumn"; then
  if ! [ -f "$tmp_dir_tmp/autumn_opt" ] || ! [ -f "$tmp_dir_tmp/autumn_opt_summary" ]; then
    echo "Error: results extraction failed." >&2
    exit 105
  fi
fi

if "$late_winter"; then
  if ! [ -f "$tmp_dir_tmp/late_winter_opt" ] || ! [ -f "$tmp_dir_tmp/late_winter_opt_summary" ]; then
    echo "Error: results extraction failed." >&2
    exit 105
  fi
fi

if ! [ "X$up_one" == "X" ]; then
  cd "$up_one" || exit 1
fi



# *** POST PROCESSING ***

# Update progress file.
echo '5' > "$tmp_dir/progress.txt"

# Define function to convert "day month" string to julian day.
function DM2JD {
  date_day="${1% *}"
  date_month="${1#* }"
  if [ "$date_month" -eq 1 ]; then
    julianDay="$date_day"
  elif [ "$date_month" -eq 2 ]; then
    julianDay="$((31+date_day))"  
  elif [ "$date_month" -eq 3 ]; then
    julianDay="$((31+28+date_day))"
  elif [ "$date_month" -eq 4 ]; then
    julianDay="$((31+28+31+date_day))"
  elif [ "$date_month" -eq 5 ]; then
    julianDay="$((31+28+31+30+date_day))"
  elif [ "$date_month" -eq 6 ]; then
    julianDay="$((31+28+31+30+31+date_day))"
  elif [ "$date_month" -eq 7 ]; then
    julianDay="$((31+28+31+30+31+30+date_day))"
  elif [ "$date_month" -eq 8 ]; then
    julianDay="$((31+28+31+30+31+30+31+date_day))"
  elif [ "$date_month" -eq 9 ]; then
    julianDay="$((31+28+31+30+31+30+31+31+date_day))"
  elif [ "$date_month" -eq 10 ]; then
    julianDay="$((31+28+31+30+31+30+31+31+30+date_day))"
  elif [ "$date_month" -eq 11 ]; then
    julianDay="$((31+28+31+30+31+30+31+31+30+31+date_day))"
  elif [ "$date_month" -eq 12 ]; then
    julianDay="$((31+28+31+30+31+30+31+31+30+31+30+date_day))"
  else
    echo "Error: unrecognised worst day month \"$date_month\"." >&2
    exit 109
  fi
}

# Define function to convert julian day to "day month" string.
function JD2DM {
  jDay=$1
  if [ "$jDay" -le 31  ]; then
    dayMonth="$jDay 1"
  elif [ "$jDay" -le 59 ]; then
    dayMonth="$((jDay-31)) 2"
  elif [ "$jDay" -le 90 ]; then
    dayMonth="$((jDay-31-28)) 3"
  elif [ "$jDay" -le 120 ]; then
    dayMonth="$((jDay-31-28-31)) 4"
  elif [ "$jDay" -le 151 ]; then
    dayMonth="$((jDay-31-28-31-30)) 5"
  elif [ "$jDay" -le 181 ]; then
    dayMonth="$((jDay-31-28-31-30-31)) 6"
  elif [ "$jDay" -le 212 ]; then
    dayMonth="$((jDay-31-28-31-30-31-30)) 7"
  elif [ "$jDay" -le 243 ]; then
    dayMonth="$((jDay-31-28-31-30-31-30-31)) 8"
  elif [ "$jDay" -le 273 ]; then
    dayMonth="$((jDay-31-28-31-30-31-30-31-31)) 9"
  elif [ "$jDay" -le 304 ]; then
    dayMonth="$((jDay-31-28-31-30-31-30-31-31-30)) 10"
  elif [ "$jDay" -le 334 ]; then
    dayMonth="$((jDay-31-28-31-30-31-30-31-31-30-31)) 11"
  elif [ "$jDay" -le 365 ]; then
    dayMonth="$((jDay-31-28-31-30-31-30-31-31-30-31-30)) 12"
  else
    echo "Error: unrecognised julian day \"$jDay\"." >&2
    exit 109
  fi
}

DM2JD "$start"
simS_JD="$julianDay"
DM2JD "$finish"
simF_JD="$julianDay"
DM2JD "$SpS"
SpS_JD="$julianDay"
DM2JD "$SpF"
SpF_JD="$julianDay"
DM2JD "$SuS"
SuS_JD="$julianDay"
DM2JD "$SuF"
SuF_JD="$julianDay"
DM2JD "$AS"
AS_JD="$julianDay"
DM2JD "$AF"
AF_JD="$julianDay"

# Calculate deviation of op temp from comfort criteria.
deviation_opt=''
if "$early_winter"; then
  deviation_opt="$deviation_opt $(awk -v criteriaU="$opt_criteria_max_win" -v criteriaL="$opt_criteria_min_win" -f "$script_dir/get_deviation_upAndLow.awk" "$tmp_dir/early_winter_opt")"
  midpoint_win="$(echo "$opt_criteria_max_win $opt_criteria_min_win" | awk '{print(($1+$2)/2.0)}')"
fi
if "$spring"; then

# We assume comfort criteria varies linearly between winter and summer limits through transition seasons.
# So, we need to calculate upper and lower limits for the period that we're running for.
  if [ "$simS_JD" -le "$SpS_JD" ] && [ "$simF_JD" -ge "$SpF_JD" ]; then
    nhead=4
    i="$(awk 'END{print NR}' "$tmp_dir/spring_opt")"
    ndata="$((i-nhead))"
    criteriaUS="$opt_criteria_max_win"
    criteriaLS="$opt_criteria_min_win"
    criteriaUF="$opt_criteria_max_sum"
    criteriaLF="$opt_criteria_min_sum"
  else
    range_JD="$((SpF_JD-SpS_JD))"
    if [ "$simS_JD" -gt "$SpS_JD" ]; then
      point_JD="$((simS_JD-SpS_JD))"
      range_criteria="$(echo "$opt_criteria_max_sum $opt_criteria_max_win" | awk '{print $1-$2}')"
      criteriaUS="$(echo '' | awk -v range_JD="$range_JD" -v range_criteria="$range_criteria" -v point_JD="$point_JD" -v min_criteria="$opt_criteria_max_win" '{print min_criteria+point_JD*range_criteria/range_JD}')"
      range_criteria="$(echo "$opt_criteria_min_sum $opt_criteria_min_win" | awk '{print $1-$2}')"
      criteriaLS="$(echo '' | awk -v range_JD="$range_JD" -v range_criteria="$range_criteria" -v point_JD="$point_JD" -v min_criteria="$opt_criteria_min_win" '{print min_criteria+point_JD*range_criteria/range_JD}')"
    else
      criteriaUS="$opt_criteria_max_win"
      criteriaLS="$opt_criteria_min_win"
    fi    
    if [ "$simF_JD" -lt "$SpF_JD" ]; then
      point_JD="$((simF_JD-SpS_JD))"
      range_criteria="$(echo "$opt_criteria_max_sum $opt_criteria_max_win" | awk '{print $1-$2}')"
      criteriaUF="$(echo '' | awk -v range_JD="$range_JD" -v range_criteria="$range_criteria" -v point_JD="$point_JD" -v min_criteria="$opt_criteria_max_win" '{print min_criteria+point_JD*range_criteria/range_JD}')"
      range_criteria="$(echo "$opt_criteria_min_sum $opt_criteria_min_win" | awk '{print $1-$2}')"
      criteriaLF="$(echo '' | awk -v range_JD="$range_JD" -v range_criteria="$range_criteria" -v point_JD="$point_JD" -v min_criteria="$opt_criteria_min_win" '{print min_criteria+point_JD*range_criteria/range_JD}')"
    else
      criteriaUF="$opt_criteria_max_sum"
      criteriaLF="$opt_criteria_min_sum"
    fi
  fi

  deviation_opt="$deviation_opt $(awk -v criteriaUS="$criteriaUS" -v criteriaLS="$criteriaLS" -v criteriaUF="$criteriaUF" -v criteriaLF="$criteriaLF" -v nhead="$nhead" -v ndata="$ndata" -f "$script_dir/get_deviation_upAndLow_linear.awk" "$tmp_dir/spring_opt")"
  midpointS_spr="$(echo "$criteriaUS $criteriaLS" | awk '{print(($1+$2)/2.0)}')"
  midpointF_spr="$(echo "$criteriaUF $criteriaLF" | awk '{print(($1+$2)/2.0)}')"
fi
if "$summer"; then
  deviation_opt="$deviation_opt $(awk -v criteriaU="$opt_criteria_max_sum" -v criteriaL="$opt_criteria_min_sum" -f "$script_dir/get_deviation_upAndLow.awk" "$tmp_dir/summer_opt")"
  midpoint_sum="$(echo "$opt_criteria_max_sum $opt_criteria_min_sum" | awk '{print(($1+$2)/2.0)}')"
fi
if "$autumn"; then

# See comments for spring above.
  if [ "$simS_JD" -le "$AS_JD" ] && [ "$simF_JD" -ge "$AF_JD" ]; then
    nhead=4
    i="$(awk 'END{print NR}' "$tmp_dir/autumn_opt")"
    ndata="$((i-nhead))"
    criteriaUS="$opt_criteria_max_sum"
    criteriaLS="$opt_criteria_min_sum"
    criteriaUF="$opt_criteria_max_win"
    criteriaLF="$opt_criteria_min_win"
  else
    range_JD="$((AF_JD-AS_JD))"
    if [ "$simS_JD" -gt "$AS_JD" ]; then
      point_JD="$((simS_JD-AS_JD))"
      range_criteria="$(echo "$opt_criteria_max_win $opt_criteria_max_sum" | awk '{print $1-$2}')"
      criteriaUS="$(echo '' | awk -v range_JD="$range_JD" -v range_criteria="$range_criteria" -v point_JD="$point_JD" -v min_criteria="$opt_criteria_max_sum" '{print min_criteria+point_JD*range_criteria/range_JD}')"
      range_criteria="$(echo "$opt_criteria_min_win $opt_criteria_min_sum" | awk '{print $1-$2}')"
      criteriaLS="$(echo '' | awk -v range_JD="$range_JD" -v range_criteria="$range_criteria" -v point_JD="$point_JD" -v min_criteria="$opt_criteria_min_sum" '{print min_criteria+point_JD*range_criteria/range_JD}')"
    else
      criteriaUS="$opt_criteria_max_sum"
      criteriaLS="$opt_criteria_min_sum"
    fi    
    if [ "$simF_JD" -lt "$AF_JD" ]; then
      point_JD="$((simF_JD-AS_JD))"
      range_criteria="$(echo "$opt_criteria_max_win $opt_criteria_max_sum" | awk '{print $1-$2}')"
      criteriaUF="$(echo '' | awk -v range_JD="$range_JD" -v range_criteria="$range_criteria" -v point_JD="$point_JD" -v min_criteria="$opt_criteria_max_sum" '{print min_criteria+point_JD*range_criteria/range_JD}')"
      range_criteria="$(echo "$opt_criteria_min_win $opt_criteria_min_sum" | awk '{print $1-$2}')"
      criteriaLF="$(echo '' | awk -v range_JD="$range_JD" -v range_criteria="$range_criteria" -v point_JD="$point_JD" -v min_criteria="$opt_criteria_min_sum" '{print min_criteria+point_JD*range_criteria/range_JD}')"
    else
      criteriaUF="$opt_criteria_max_win"
      criteriaLF="$opt_criteria_min_win"
    fi
  fi
  deviation_opt="$deviation_opt $(awk -v criteriaUS="$criteriaUS" -v criteriaLS="$criteriaLS" -v criteriaUF="$criteriaUF" -v criteriaLF="$criteriaLF" -v nhead="$nhead" -v ndata="$ndata" -f "$script_dir/get_deviation_upAndLow_linear.awk" "$tmp_dir/autumn_opt")"
  midpointS_aut="$(echo "$criteriaUS $criteriaLS" | awk '{print(($1+$2)/2.0)}')"
  midpointF_aut="$(echo "$criteriaUF $criteriaLF" | awk '{print(($1+$2)/2.0)}')"
fi
if "$late_winter"; then
  deviation_opt="$deviation_opt $(awk -v criteriaU="$opt_criteria_max_win" -v criteriaL="$opt_criteria_min_win" -f "$script_dir/get_deviation_upAndLow.awk" "$tmp_dir/late_winter_opt")"
  midpoint_win="$(echo "$opt_criteria_max_win $opt_criteria_min_win" | awk '{print(($1+$2)/2.0)}')"
fi

echo "$deviation_opt" > "$tmp_dir/deviation_opt.trace"

# Deviation for other comfort metrics.
deviation_floor="$(awk -v criteria="$floor_criteria" -f "$script_dir/get_deviation.awk" "$tmp_dir/floor_discomfort")"
echo "$deviation_floor" > "$tmp_dir/deviation_floor.trace"
deviation_ceiling="$(awk -v criteria="$asym_criteria" -f "$script_dir/get_deviation.awk" "$tmp_dir/ceiling_discomfort")"
echo "$deviation_ceiling" > "$tmp_dir/deviation_ceiling.trace"
deviation_wall="$(awk -v criteria="$asym_criteria" -f "$script_dir/get_deviation.awk" "$tmp_dir/wall_discomfort")"
echo "$deviation_wall" > "$tmp_dir/deviation_wall.trace"
if $is_CFDandMRT; then
  deviation_vertdT="$(awk -v criteria="$vertdT_criteria" -f "$script_dir/get_deviation.awk" "$tmp_dir/vertdT_discomfort")"
  echo "$deviation_vertdT" > "$tmp_dir/deviation_vertdT.trace"
  deviation_draught="$(awk -v criteria="$draught_criteria" -f "$script_dir/get_deviation.awk" "$tmp_dir/draught_discomfort")"
  echo "$deviation_draught" > "$tmp_dir/deviation_draught.trace"
fi

# Find percentage of occupied time in discomfort (PTD).
PTD_opt="$(echo "$deviation_opt" | awk -f "$script_dir/get_percentTimeDiscomfort.awk")"
array_PTD_opt=($PTD_opt)

# Simulation period in days.
DM2JD "$start_day $start_month"
start_jDay="$julianDay"
DM2JD "$finish_day $finish_month"
finish_jDay="$julianDay"
simPeriod_days="$((finish_day-start_day+1))"

# If the simulation period is more than one day ...
if [ "$simPeriod_days" -gt 1 ]; then

  # Get daily-mean indoor operative temperature during occupied hours.
  # First column is day number, second column is optimum temperature (assumed to be midpoint of comfort range).
  rm "$tmp_dir/DMoptWO" >/dev/null 2>&1
  touch "$tmp_dir/DMoptWO"
  if "$early_winter"; then
    awk -f "$script_dir/get_dailyMean.awk" "$tmp_dir/early_winter_opt" > "$tmp_dir/early_winter_DMopt"
    nhead=0
    i="$(awk 'END{print NR}' "$tmp_dir/early_winter_DMopt")"
    ndata="$((i-nhead))"
    awk -v nhead="$nhead" -v ndata="$ndata" -v optimumS="$midpoint_win" -v optimumF="$midpoint_win" -f "$script_dir/add_optimum_to_dailyMean.awk" "$tmp_dir/early_winter_DMopt" >> "$tmp_dir/DMoptWO"
  fi
  if "$spring"; then
    awk -f "$script_dir/get_dailyMean.awk" "$tmp_dir/spring_opt" > "$tmp_dir/spring_DMopt"
    nhead=0
    i="$(awk 'END{print NR}' "$tmp_dir/spring_DMopt")"
    ndata="$((i-nhead))"
    awk -v nhead="$nhead" -v ndata="$ndata" -v optimumS="$midpointS_spr" -v optimumF="$midpointF_spr" -f "$script_dir/add_optimum_to_dailyMean.awk" "$tmp_dir/spring_DMopt" >> "$tmp_dir/DMoptWO"
  fi
  if "$summer"; then
    awk -f "$script_dir/get_dailyMean.awk" "$tmp_dir/summer_opt" > "$tmp_dir/summer_DMopt"
    nhead=0
    i="$(awk 'END{print NR}' "$tmp_dir/summer_DMopt")"
    ndata="$((i-nhead))"
    awk -v nhead="$nhead" -v ndata="$ndata" -v optimumS="$midpoint_sum" -v optimumF="$midpoint_sum" -f "$script_dir/add_optimum_to_dailyMean.awk" "$tmp_dir/summer_DMopt" >> "$tmp_dir/DMoptWO"
  fi
  if "$autumn"; then
    awk -f "$script_dir/get_dailyMean.awk" "$tmp_dir/autumn_opt" > "$tmp_dir/autumn_DMopt"
    nhead=0
    i="$(awk 'END{print NR}' "$tmp_dir/autumn_DMopt")"
    ndata="$((i-nhead))"
    awk -v nhead="$nhead" -v ndata="$ndata" -v optimumS="$midpointS_aut" -v optimumF="$midpointF_aut" -f "$script_dir/add_optimum_to_dailyMean.awk" "$tmp_dir/autumn_DMopt" >> "$tmp_dir/DMoptWO"
  fi
  if "$late_winter"; then
    awk -f "$script_dir/get_dailyMean.awk" "$tmp_dir/late_winter_opt" > "$tmp_dir/late_winter_DMopt"
    nhead=0
    i="$(awk 'END{print NR}' "$tmp_dir/late_winter_DMopt")"
    ndata="$((i-nhead))"
    awk -v nhead="$nhead" -v ndata="$ndata" -v optimumS="$midpoint_win" -v optimumF="$midpoint_win" -f "$script_dir/add_optimum_to_dailyMean.awk" "$tmp_dir/late_winter_DMopt" >> "$tmp_dir/DMoptWO"
  fi

  # Assess day-to-day temperature drift.
  deviation_optDD="$(awk -v criteria="$DMopt_daily_drift_criteria" -f "$script_dir/get_deviation_dailyTemperatureDrift.awk" "$tmp_dir/DMoptWO")"
  echo "$deviation_optDD" > "$tmp_dir/deviation_optDD.trace"
  deviation_optDDWD="$(awk -v criteria="$DMopt_daily_drift_criteria" -f "$script_dir/get_deviation_dailyTemperatureDrift_withDay.awk" "$tmp_dir/DMoptWO")"
  echo "$deviation_optDD" > "$tmp_dir/deviation_optDD.trace"
  echo "$deviation_optDDWD" > "$tmp_dir/deviation_optDDWD.trace"
  PTD_optDD="$(echo "$deviation_optDD" | awk -f "$script_dir/get_percentTimeDiscomfort.awk")"
  echo "$PTD_optDD" > "$tmp_dir/PTD_optDD.trace"
  array_PTD_optDD=($PTD_optDD)
  severity_optDD="$(echo "$PTD_optDD" | awk -f "$script_dir/get_severityRating.awk")"
  echo "$severity_optDD" > "$tmp_dir/severity_optDD.trace"
  array_severity_optDD=($severity_optDD)
  DWD_optDD="$(echo "$deviation_optDDWD" | awk -f "$script_dir/get_dayWorstDiscomfort.awk")"
  echo "$DWD_optDD" > "$tmp_dir/DWD_optDD.trace"
  array_DWD_optDD=($DWD_optDD)

  # If the simulation period is 7 days or greater, assess weekly temperature drift.
  if [ "$simPeriod_days" -ge 7 ]; then
    deviation_optWD="$(awk -v criteria="$DMopt_weekly_drift_criteria" -f "$script_dir/get_deviation_weeklyTemperatureDrift.awk" "$tmp_dir/DMoptWO")"
    echo "$deviation_optWD" > "$tmp_dir/deviation_optWD.trace"
    deviation_optWDWD="$(awk -v criteria="$DMopt_weekly_drift_criteria" -f "$script_dir/get_deviation_weeklyTemperatureDrift_withDay.awk" "$tmp_dir/DMoptWO")"
    echo "$deviation_optWDWD" > "$tmp_dir/deviation_optWDWD.trace"
    PTD_optWD="$(echo "$deviation_optWD" | awk -f "$script_dir/get_percentTimeDiscomfort.awk")"
    echo "$PTD_optWD" > "$tmp_dir/PTD_optWD.trace"
    array_PTD_optWD=($PTD_optWD)
    severity_optWD="$(echo "$PTD_optWD" | awk -f "$script_dir/get_severityRating.awk")"
    echo "$severity_optWD" > "$tmp_dir/severity_optWD.trace"
    array_severity_optWD=($severity_optWD)
    DWD_optWD="$(echo "$deviation_optWDWD" | awk -f "$script_dir/get_dayWorstDiscomfort.awk")"
    echo "$DWD_optWD" > "$tmp_dir/DWD_optWD.trace"
    array_DWD_optWD=($DWD_optWD)
  fi
fi

# # Calculate percentages of cold and hot discomfort (PHD, PCD)
# PHD_opt="$(echo "$deviation_opt" | awk -f "$script_dir/get_percentHotDiscomfort.awk")"
# array_PHD_opt=($PHD_opt)
# i=0
# for a in "${array_PHD_opt[@]}"; do
#   array_PCD_opt[i]="$((100-a))"
#   ((i++))
# done

# Assemble comma seperated list of number of floor surfaces for each zone, for awk call below.
first=true
for a in "${array_num_floor_surfaces[@]}"; do
  if $first; then
    num_floorCols="$a"
    first=false
  else
    num_floorCols="${num_floorCols},${a}"
  fi
done

# Percentage time in discomfort for other metrics.
PTD_floor="$(echo "$deviation_floor" | awk -v ncols="$num_floorCols" -f "$script_dir/get_variableMulticolumnPercentTimeDiscomfort.awk")"
array_PTD_floor=($PTD_floor)
PTD_ceiling="$(echo "$deviation_ceiling" | awk -f "$script_dir/get_percentTimeDiscomfort.awk")"
array_PTD_ceiling=($PTD_ceiling)
PTD_wall="$(echo "$deviation_wall" | awk -v ncols=4 -f "$script_dir/get_multicolumnPercentTimeDiscomfort.awk")"
array_PTD_wall=($PTD_wall)
if $is_CFDandMRT; then
  PTD_vertdT="$(echo "$deviation_vertdT" | awk -f "$script_dir/get_percentTimeDiscomfort.awk")"
  array_PTD_vertdT=($PTD_vertdT)
  PTD_draught="$(echo "$deviation_draught" | awk -f "$script_dir/get_percentTimeDiscomfort.awk")"
  array_PTD_draught=($PTD_draught)
fi

echo "${array_PTD_opt[@]}" > "$tmp_dir/PTD_opt.trace"
echo "${array_PTD_floor[@]}" > "$tmp_dir/PTD_floor.trace"
echo "${array_PTD_ceiling[@]}" > "$tmp_dir/PTD_ceiling.trace"
echo "${array_PTD_wall[@]}" > "$tmp_dir/PTD_wall.trace"
echo "${array_PTD_vertdT[@]}" > "$tmp_dir/PTD_vertdT.trace"
echo "${array_PTD_draught[@]}" > "$tmp_dir/PTD_draught.trace"

# Calculate severity ratings.
severity_opt="$(echo "$PTD_opt" | awk -f "$script_dir/get_severityRating.awk")"
array_severity_opt=($severity_opt)
severity_floor="$(echo "$PTD_floor" | awk -v ncols="$num_floorCols" -f "$script_dir/get_severityRating.awk")"
array_severity_floor=($severity_floor)
severity_ceiling="$(echo "$PTD_ceiling" | awk -f "$script_dir/get_severityRating.awk")"
array_severity_ceiling=($severity_ceiling)
severity_wall="$(echo "$PTD_wall" | awk -f "$script_dir/get_severityRating.awk")"
array_severity_wall=($severity_wall)
if $is_CFDandMRT; then
  severity_vertdT="$(echo "$PTD_vertdT" | awk -f "$script_dir/get_severityRating.awk")"
  array_severity_vertdT=($severity_vertdT)
  severity_draught="$(echo "$PTD_draught" | awk -f "$script_dir/get_severityRating.awk")"
  array_severity_draught=($severity_draught)
fi

echo "${array_severity_opt[@]}" > "$tmp_dir/severity_opt.trace"
echo "${array_severity_floor[@]}" > "$tmp_dir/severity_floor.trace"
echo "${array_severity_ceiling[@]}" > "$tmp_dir/severity_ceiling.trace"
echo "${array_severity_wall[@]}" > "$tmp_dir/severity_wall.trace"
echo "${array_severity_vertdT[@]}" > "$tmp_dir/severity_vertdT.trace"
echo "${array_severity_draught[@]}" > "$tmp_dir/severity_draught.trace"

# Assemble overall severity arrays (per zone and per sensor) using the worst from all comfort metrics.
# Also set performance flag if any discomfort is found.
array_zone_severity=''
for i in "${array_zone_indices[@]}"; do
  array_zone_severity=(${array_zone_severity[@]} '-1')
done

performance_flag=0

is_opt_discomfort=false
is_floor_discomfort=false
is_ceiling_discomfort=false
is_wall_discomfort=false
is_vertdT_discomfort=false
is_draught_discomfort=false
is_optDD_discomfort=false
is_optWD_discomfort=false

iz0=-1
iCFDs0=-1
for is0 in "${array_sensor_indices[@]}"; do

  # Is there any discomfort for each metric?
  if ! "$is_opt_discomfort"; then
    if [ "${array_severity_opt[is0]}" -gt 0 ]; then is_opt_discomfort=true; fi
  fi
  if ! "$is_ceiling_discomfort"; then
    if [ "${array_severity_ceiling[is0]}" -gt 0 ]; then is_ceiling_discomfort=true; fi
  fi
  if ! "$is_wall_discomfort"; then
    if [ "${array_severity_wall[is0]}" -gt 0 ]; then is_wall_discomfort=true; fi
  fi
  if "$is_CFD"; then
    iz1="${array_sensor_zones[is0]}"
    iz0="$((iz1-1))"
    if [ "${array_CFD_domains[iz0]}" -gt 1 ]; then
      ((iCFDs0++))
      if ! "$is_vertdT_discomfort"; then
        if [ "${array_severity_vertdT[iCFDs0]}" -gt 0 ]; then is_vertdT_discomfort=true; fi
      fi
      if ! "$is_draught_discomfort"; then
        if [ "${array_severity_draught[iCFDs0]}" -gt 0 ]; then is_draught_discomfort=true; fi
      fi
    fi
  fi
  if [ "$simPeriod_days" -gt 1 ]; then
    if ! "$is_optDD_discomfort"; then
      if [ "${array_severity_optDD[is0]}" -gt 0 ]; then is_optDD_discomfort=true; fi
    fi
  fi
  if [ "$simPeriod_days" -ge 7 ]; then
    if ! "$is_optWD_discomfort"; then
      if [ "${array_severity_optWD[is0]}" -gt 0 ]; then is_optWD_discomfort=true; fi
    fi
  fi    

  sev="${array_severity_opt[is0]}"
  iz0prev="$iz0"
  iz0="$((array_sensor_zones[is0]-1))"

  if ! "$is_floor_discomfort"; then
    if [ "${array_severity_floor[iz0]}" -gt 0 ]; then is_floor_discomfort=true; fi
  fi

  sevs="${array_severity_floor[iz0]} ${array_severity_ceiling[is0]} ${array_severity_wall[is0]}"
  if [ "${array_CFD_domains[iz0]}" -eq 2 ]; then
    sevs="$sevs ${array_severity_vertdT[iCFDs0]} ${array_severity_draught[iCFDs0]}"
  fi
  if [ "$simPeriod_days" -gt 1 ]; then
    sevs="$sevs ${array_severity_optDD[is0]}"
  fi
  if [ "$simPeriod_days" -ge 7 ]; then
    sevs="$sevs ${array_severity_optWD[is0]}"
  fi

  for next_sev in $sevs; do
    if [ "$next_sev" -gt "$sev" ]; then
      sev="$next_sev"
    fi
    if [ "$sev" -eq 1 ]; then 
      performance_flag=1
      break
    fi
  done
  array_sensor_severity[is0]="$sev"

  next_sev="$sev"
  sev="${array_zone_severity[iz0]}"
  if [ "$next_sev" -gt "$sev" ]; then
    sev="$next_sev"
  fi
  array_zone_severity[iz0]="$sev"
done

echo "$performance_flag" > "$tmp_dir/pflag.txt"

# If there is CFD, for each location, write out time series csv of
# air temperature, air velocity, CO2, MRT and all comfort metrics.
if $is_CFDandMRT; then

  # Operative temperature.
  opt_awk_input=''
  if "$early_winter"; then opt_awk_input="$opt_awk_input $tmp_dir/early_winter_opt"; fi  
  if "$spring"; then opt_awk_input="$opt_awk_input $tmp_dir/spring_opt"; fi
  if "$summer"; then opt_awk_input="$opt_awk_input $tmp_dir/summer_opt"; fi
  if "$autumn"; then opt_awk_input="$opt_awk_input $tmp_dir/autumn_opt"; fi
  if "$late_winter"; then opt_awk_input="$opt_awk_input $tmp_dir/late_winter_opt"; fi

  for i1_zone in "${array_zones_with_MRTsensors[@]}"; do  
    i0_zone="$((i1_zone-1))"

    i1_sensor=0
    i2_sensor=1
    i2_column=1
    while [ "$i1_sensor" -lt "${array_MRT_sensors[i0_zone]}" ]; do
      ((i1_sensor++))
      ((i2_sensor++))
      ((i2_column++))
      opt="$(awk -v col="$i2_column" -f "$script_dir/get_singleColumnWithTime.awk" $opt_awk_input)"
      printf "#Time Operative_temperature_C\n$opt\n" > "$tmp_dir/zone${i1_zone}_sensor${i1_sensor}_opt.txt"
    done
  done

  # Floor discomfort.
  i2_col=2
  for i0_zone in "${array_zone_indices[@]}"; do
    i1_zone="$((i0_zone+1))"
    if [ "${array_num_floor_surfaces[i0_zone]}" -gt 0 ]; then
      cols="$i2_col"
      ((i2_col++))
      i1_flr=2
      while [ "$i1_flr" -le "${array_num_floor_surfaces[i0_zone]}" ]; do
        cols="$cols,$i2_col"
        ((i2_col++))
        ((i1_flr++))
      done
      floor="$(awk -v cols="$cols" -f "$script_dir/get_multicolumnMaxWithTime.awk" "$tmp_dir/floor_discomfort")"
      printf "#Time Floor_temperature_PD\n$floor\n" > "$tmp_dir/zone${i1_zone}_floor.txt"
    fi
  done

  # Radiant asymmetry - ceiling.
  for i1_zone in "${array_zones_with_MRTsensors[@]}"; do  
    i0_zone="$((i1_zone-1))"

    i1_sensor=0
    i2_sensor=1
    i2_column=1
    while [ "$i1_sensor" -lt "${array_MRT_sensors[i0_zone]}" ]; do
      ((i1_sensor++))
      ((i2_sensor++))
      ((i2_column++))
      ceiling="$(awk -v col="$i2_column" -f "$script_dir/get_singleColumnWithTime.awk" "$tmp_dir/ceiling_discomfort")"
      printf "#Time Ceiling_temperature_PD\n$ceiling\n" > "$tmp_dir/zone${i1_zone}_sensor${i1_sensor}_ceiling.txt"
    done
  done

  # Radiant asymmetry - walls.
  i2_column=2
  for i1_zone in "${array_zones_with_MRTsensors[@]}"; do  
    i0_zone="$((i1_zone-1))"

    i1_sensor=0
    i2_sensor=1
    while [ "$i1_sensor" -lt "${array_MRT_sensors[i0_zone]}" ]; do
      ((i1_sensor++))
      ((i2_sensor++))
      cols="$i2_column"
      ((i2_column++))
      cols="$cols,$i2_column"
      ((i2_column++))
      cols="$cols,$i2_column"
      ((i2_column++))
      cols="$cols,$i2_column"
      ((i2_column++))
      wall="$(awk -v cols="$cols" -f "$script_dir/get_multicolumnMaxWithTime.awk" $tmp_dir/wall_discomfort)"
      printf "#Time Wall_temperature_PD\n$wall\n" > "$tmp_dir/zone${i1_zone}_sensor${i1_sensor}_wall.txt"
    done
  done

  # Vertical air temperature difference.
  for i1_zone in "${array_zones_with_MRTsensors[@]}"; do  
    i0_zone="$((i1_zone-1))"

    i1_sensor=0
    i2_sensor=1
    i2_column=1
    while [ "$i1_sensor" -lt "${array_MRT_sensors[i0_zone]}" ]; do
      ((i1_sensor++))
      ((i2_sensor++))
      ((i2_column++))
      vertdT="$(awk -v col="$i2_column" -f "$script_dir/get_singleColumnWithTime.awk" $tmp_dir/vertdT_discomfort)"
      printf "#Time HeadToFoot_airTemperature_difference_PD\n$vertdT\n" > "$tmp_dir/zone${i1_zone}_sensor${i1_sensor}_vertdT.txt"
    done
  done

  # Draught.
  for i1_zone in "${array_zones_with_MRTsensors[@]}"; do  
    i0_zone="$((i1_zone-1))"

    i1_sensor=0
    i2_sensor=1
    i2_column=1
    while [ "$i1_sensor" -lt "${array_MRT_sensors[i0_zone]}" ]; do
      ((i1_sensor++))
      ((i2_sensor++))
      ((i2_column++))
      draught="$(awk -v col="$i2_column" -f "$script_dir/get_singleColumnWithTime.awk" $tmp_dir/draught_discomfort)"
      printf "#Time Draught_PD\n$draught\n" > "$tmp_dir/zone${i1_zone}_sensor${i1_sensor}_draught.txt"
    done
  done
  
  # Create CSV files.
  for i1_zone in "${array_zones_with_CFDandMRT[@]}"; do  
    i0_zone="$((i1_zone-1))"

    i1_sensor=0
    while [ "$i1_sensor" -lt "${array_MRT_sensors[i0_zone]}" ]; do
      ((i1_sensor++))

      # Redo header lines of cfd and zone time series.
      sed -e 's/^#Time .*$/#Time MRT_C/' -i "$tmp_dir/zone${i1_zone}_sensor${i1_sensor}_zonetimeseries.txt"
      sed -e 's/^#Time .*$/#Time Air_temperature_C Air_velocity_m\/s CO2_concentration_g\/kg/' -i "$tmp_dir/zone${i1_zone}_sensor${i1_sensor}_cfdtimeseries.txt"

      # Assemble CSV.
      awk -f "$script_dir/combine_columnDataCSV.awk" "$tmp_dir/zone${i1_zone}_sensor${i1_sensor}_opt.txt" "$tmp_dir/zone${i1_zone}_floor.txt" "$tmp_dir/zone${i1_zone}_sensor${i1_sensor}_ceiling.txt" "$tmp_dir/zone${i1_zone}_sensor${i1_sensor}_wall.txt" "$tmp_dir/zone${i1_zone}_sensor${i1_sensor}_vertdT.txt" "$tmp_dir/zone${i1_zone}_sensor${i1_sensor}_draught.txt" "$tmp_dir/zone${i1_zone}_sensor${i1_sensor}_zonetimeseries.txt" "$tmp_dir/zone${i1_zone}_sensor${i1_sensor}_cfdtimeseries.txt" > "$tmp_dir/zone${i1_zone}_sensor${i1_sensor}_timeSeries.csv"
    done
  done
  cd $tmp_dir
  if [ ! -d '../outputs' ]; then mkdir '../outputs'; fi
  tar -czf '../outputs/timeseries.tar.gz' *.csv
  cd ..
fi

if "$do_detailed_report"; then

  # For each location with discomfort, dump data for each metric during occupied hours into separate file for graphing.
  # Operative temperature.
  if "$is_opt_discomfort"; then
    opt_awk_input=''
    if "$early_winter"; then opt_awk_input="$opt_awk_input $tmp_dir/early_winter_opt"; fi  
    if "$spring"; then opt_awk_input="$opt_awk_input $tmp_dir/spring_opt"; fi
    if "$summer"; then opt_awk_input="$opt_awk_input $tmp_dir/summer_opt"; fi
    if "$autumn"; then opt_awk_input="$opt_awk_input $tmp_dir/autumn_opt"; fi
    if "$late_winter"; then opt_awk_input="$opt_awk_input $tmp_dir/late_winter_opt"; fi

    for i0_sen in "${array_sensor_indices[@]}"; do
      if [ "${array_severity_opt[i0_sen]}" -gt 0 ]; then
        i1_sen="$((i0_sen+1))"
        i=1
        output="$(awk -v zone="$i1_sen" -v recursion="$i" -f "$script_dir/get_singleZoneAllRecursive.awk" $opt_awk_input)"
        while [ ! "X$output" == "X" ]; do
          echo "$output" > "$tmp_dir/sen$i0_sen-opt-$i.txt"
          ((i++))    
          output="$(awk -v zone="$i1_sen" -v recursion="$i" -f "$script_dir/get_singleZoneAllRecursive.awk" $opt_awk_input)"
        done
        array_num_opt_plotFiles[i0_sen]="$((i-1))"
      else
        array_num_opt_plotFiles[i0_sen]=0
      fi
    done
  fi

  # Floor discomfort.
  if "$is_floor_discomfort"; then
    i2_col=2
    for i0_zone in "${array_zone_indices[@]}"; do
      if [ "${array_num_floor_surfaces[i0_zone]}" -gt 0 ]; then
        if [ "${array_severity_floor[i0_zone]}" -gt 0 ]; then
          cols="$i2_col"
          ((i2_col++))
          i1_flr=2
          while [ "$i1_flr" -le "${array_num_floor_surfaces[i0_zone]}" ]; do
            cols="$cols,$i2_col"
            ((i2_col++))
            ((i1_flr++))
          done
          i=1
          output="$(awk -v cols="$cols" -v recursion="$i" -f "$script_dir/get_multicolumnMaxRecursive.awk" "$tmp_dir/floor_discomfort")"
          while [ ! "X$output" == "X" ]; do
            echo "$output" > "$tmp_dir/zon$i0_zone-floor-$i.txt"
            ((i++))    
            output="$(awk -v cols="$cols" -v recursion="$i" -f "$script_dir/get_multicolumnMaxRecursive.awk" "$tmp_dir/floor_discomfort")"
          done
          array_num_floor_plotFiles[i0_zone]="$((i-1))"
        else
          ((i2_col+=array_num_floor_surfaces[i0_zone]))
        fi
      fi
    done
  fi

  # Radiant asymmetry - ceiling.
  if "$is_ceiling_discomfort"; then
    for i0_sen in "${array_sensor_indices[@]}"; do
      if [ "${array_severity_ceiling[i0_sen]}" -gt 0 ]; then
        i1_sen="$((i0_sen+1))"
        i=1
        output="$(awk -v zone="$i1_sen" -v recursion="$i" -f "$script_dir/get_singleZoneAllRecursive.awk" "$tmp_dir/ceiling_discomfort")"
        while [ ! "X$output" == "X" ]; do
          echo "$output" > "$tmp_dir/sen$i0_sen-ceil-$i.txt"
          ((i++))    
          output="$(awk -v zone="$i1_sen" -v recursion="$i" -f "$script_dir/get_singleZoneAllRecursive.awk" "$tmp_dir/ceiling_discomfort")"
        done
        array_num_ceil_plotFiles[i0_sen]="$((i-1))"
      else
        array_num_ceil_plotFiles[i0_sen]=0
      fi
    done
  fi

  # Radiant asymmetry - walls.
  if "$is_wall_discomfort"; then
    i2_col=2
    for i0_sen in "${array_sensor_indices[@]}"; do
      if [ "${array_severity_wall[i0_sen]}" -gt 0 ]; then
        cols="$i2_col"
        ((i2_col++))
        cols="$cols,$i2_col"
        ((i2_col++))
        cols="$cols,$i2_col"
        ((i2_col++))
        cols="$cols,$i2_col"
        ((i2_col++))
        i=1
        output="$(awk -v cols="$cols" -v recursion="$i" -f "$script_dir/get_multicolumnMaxRecursive.awk" $tmp_dir/wall_discomfort)"
        while [ ! "X$output" == "X" ]; do
          echo "$output" > "$tmp_dir/sen$i0_sen-wall-$i.txt"
          ((i++))    
          output="$(awk -v cols="$cols" -v recursion="$i" -f "$script_dir/get_multicolumnMaxRecursive.awk" $tmp_dir/wall_discomfort)"
        done
        array_num_wall_plotFiles[i0_sen]="$((i-1))"
      else
        array_num_wall_plotFiles[i0_sen]=0
        ((i2_col+=4))
      fi
    done
  fi

  if $is_CFDandMRT; then

    # Vertical air temperature difference.
    if "$is_vertdT_discomfort"; then
      i0_CFDsen=-1
      for i0_sen in "${array_sensor_indices[@]}"; do
        iz0="$((array_sensor_zones[i0_sen]-1))"
        if [ "${array_CFD_domains[iz0]}" -gt 1 ]; then
          ((i0_CFDsen++))
          if [ "${array_severity_vertdT[i0_CFDsen]}" -gt 0 ]; then
            i1_CFDsen="$((i0_CFDsen+1))"
            i=1
            output="$(awk -v zone="$i1_CFDsen" -v recursion="$i" -f "$script_dir/get_singleZoneAllRecursive.awk" $tmp_dir/vertdT_discomfort)"
            while [ ! "X$output" == "X" ]; do
              echo "$output" > "$tmp_dir/sen$i0_sen-vertdT-$i.txt"
              ((i++))    
              output="$(awk -v zone="$i1_CFDsen" -v recursion="$i" -f "$script_dir/get_singleZoneAllRecursive.awk" $tmp_dir/vertdT_discomfort)"
            done
            array_num_vertdT_plotFiles[i0_sen]="$((i-1))"
          else
            array_num_vertdT_plotFiles[i0_sen]=0
          fi
        fi
      done
    fi

    # Draught.
    # TODO update for some CFD zone, like vertdt above
    if "$is_draught_discomfort"; then
      for i0_sen in "${array_sensor_indices[@]}"; do
        if [ "${array_severity_draught[i0_sen]}" -gt 0 ]; then
          i1_sen="$((i0_sen+1))"
          i=1
          output="$(awk -v zone="$i1_sen" -v recursion="$i" -f "$script_dir/get_singleZoneAllRecursive.awk" $tmp_dir/draught_discomfort)"
          while [ ! "X$output" == "X" ]; do
            echo "$output" > "$tmp_dir/sen$i0_sen-draught-$i.txt"
            ((i++))    
            output="$(awk -v zone="$i1_sen" -v recursion="$i" -f "$script_dir/get_singleZoneAllRecursive.awk" $tmp_dir/draught_discomfort)"
          done
          array_num_draught_plotFiles[i0_sen]="$((i-1))"
        else
          array_num_draught_plotFiles[i0_sen]=0
        fi
      done
    fi
  fi

  # Daily mean temperature.
  if "$is_optDD_discomfort" || "$is_optWD_discomfort"; then
    DMopt_awk_input=''
    if "$early_winter"; then DMopt_awk_input="$DMopt_awk_input $tmp_dir/early_winter_DMopt"; fi  
    if "$spring"; then DMopt_awk_input="$DMopt_awk_input $tmp_dir/spring_DMopt"; fi
    if "$summer"; then DMopt_awk_input="$DMopt_awk_input $tmp_dir/summer_DMopt"; fi
    if "$autumn"; then DMopt_awk_input="$DMopt_awk_input $tmp_dir/autumn_DMopt"; fi
    if "$late_winter"; then DMopt_awk_input="$DMopt_awk_input $tmp_dir/late_winter_DMopt"; fi
    
    for i0_sen in "${array_sensor_indices[@]}"; do
      if [ "${array_severity_optDD[i0_sen]}" -gt 0 ] || [ "${array_severity_optWD[i0_sen]}" -gt 0 ]; then
        i1_sen="$((i0_sen+1))"
        i=1
        output="$(awk -v zone="$i1_sen" -v recursion="$i" -f "$script_dir/get_singleZoneAllRecursive.awk" $DMopt_awk_input)"
        while [ ! "X$output" == "X" ]; do
          echo "$output" > "$tmp_dir/sen$i0_sen-DMopt-$i.txt"
          ((i++))    
          output="$(awk -v zone="$i1_sen" -v recursion="$i" -f "$script_dir/get_singleZoneAllRecursive.awk" $DMopt_awk_input)"
        done
        array_num_DMopt_plotFiles[i0_sen]="$((i-1))"

        # Also create coordinates for highlighting where comfort was violated.
        i3_col="$((i0_sen+3))"
        i=1
        output="$(awk -v criteria="$DMopt_daily_drift_criteria" -v col="$i3_col" -v recursion="$i" -f "$script_dir/get_singleColumn_dailyTemperatureDriftHighlights_recursive.awk" "$tmp_dir/DMoptWO")"
        while [ ! "X$output" == "X" ]; do
          echo "$output" > "$tmp_dir/sen$i0_sen-DMoptDailyHilite-$i.txt"
          ((i++))    
        output="$(awk -v criteria="$DMopt_daily_drift_criteria" -v col="$i3_col" -v recursion="$i" -f "$script_dir/get_singleColumn_dailyTemperatureDriftHighlights_recursive.awk" "$tmp_dir/DMoptWO")"
        done
        array_num_DMoptDailyHilite_plotFiles[i0_sen]="$((i-1))"

        i=1
        output="$(awk -v criteria="$DMopt_weekly_drift_criteria" -v col="$i3_col" -v recursion="$i" -f "$script_dir/get_singleColumn_weeklyTemperatureDriftHighlights_recursive.awk" "$tmp_dir/DMoptWO")"
        while [ ! "X$output" == "X" ]; do
          echo "$output" > "$tmp_dir/sen$i0_sen-DMoptWeeklyHilite-$i.txt"
          ((i++))    
        output="$(awk -v criteria="$DMopt_weekly_drift_criteria" -v col="$i3_col" -v recursion="$i" -f "$script_dir/get_singleColumn_weeklyTemperatureDriftHighlights_recursive.awk" "$tmp_dir/DMoptWO")"
        done
        array_num_DMoptWeeklyHilite_plotFiles[i0_sen]="$((i-1))"

      else
        array_num_DMopt_plotFiles[i0_sen]=0
        array_num_DMoptDailyHilite_plotFiles[i0_sen]=0
        array_num_DMoptWeeklyHilite_plotFiles[i0_sen]=0
      fi
    done
  fi
fi

# Update progress file.
echo '6' > "$tmp_dir/progress.txt"    



# *** Write JSON file ***

echo '{' > "$JSON"

# If there is any discomfort, write directives.
if [ "$performance_flag" -gt 0 ]; then
  echo "  \"thermal discomfort\": [" >> "$JSON"
  first2=true
  i1_floor=0
  i0_zone=-1
  for i0_sensor in "${array_sensor_indices[@]}"; do
    if [ "${array_sensor_severity[i0_sensor]}" -gt 0 ]; then
      ((count++))
      if $first2; then
        first2=false
      else
        echo "," >> "$JSON"
      fi
      echo '    {' >> "$JSON"
      i1_floor="$i0_zone"
      i0_zone="$((array_sensor_zones[i0_sensor]-1))"
      i1_zone="$((i0_zone+1))"
      if [ "$i0_zone" -gt "$iz0prev" ]; then ((i1_floor++)); fi
      zone_name=${array_zone_names[i0_zone]}
      echo "      \"area\": \"$zone_name\"," >> "$JSON"
      sensor_name="${array_MRTsensor_names[i0_sensor]}"
      echo "      \"location\": \"$sensor_name\"," >> "$JSON"
      first=true    
      if [ "${array_severity_opt[i0_sensor]}" -gt 0 ]; then
        if $first; then
          first=false
        else
          echo "," >> "$JSON"
        fi
        echo "      \"operative temperature\": {" >> "$JSON"
        echo "        \"frequency of occurrence (%)\": \"${array_PTD_opt[i0_sensor]}\"," >> "$JSON"
        x="$(awk -v zoneName=$zone_name -v sensorName=$sensor_name -f "$script_dir/get_sensorStats.awk" "$tmp_dir/all_opt_summary")"
        a=($x)
        s="${a[0]}/${a[1]}/$year @ ${a[2]}"
        echo "        \"worst time\": \"$s\"" >> "$JSON"
        printf "      }" >> "$JSON"
      fi
      if [ "${array_severity_floor[i0_zone]}" -gt 0 ]; then
        if $first; then
          first=false
        else
          echo "," >> "$JSON"
        fi
        echo "      \"floor temperature\": {" >> "$JSON"
        echo "        \"frequency of occurrence (%)\": \"${array_PTD_floor[i0_zone]}\"," >> "$JSON"
        x="$(awk -v entryNum="$i1_zone" -f "$script_dir/get_sensorStats.awk" "$tmp_dir/floor_summary")"
        a=($x)
        s="${a[0]}/${a[1]}/$year @ ${a[2]}"
        echo "        \"worst time\": \"$s\"" >> "$JSON"
        printf "      }" >> "$JSON"
      fi
      if [ "${array_severity_ceiling[i0_sensor]}" -gt 0 ]; then
        if $first; then
          first=false
        else
          echo "," >> "$JSON"
        fi
        echo "      \"radiant asymmetry (ceiling)\": {" >> "$JSON"
        echo "        \"frequency of occurrence (%)\": \"${array_PTD_ceiling[i0_sensor]}\"," >> "$JSON"
        x="$(awk -v zoneName=$zone_name -v sensorName=$sensor_name -f "$script_dir/get_sensorStats.awk" "$tmp_dir/ceiling_summary")"
        a=($x)
        s="${a[0]}/${a[1]}/$year @ ${a[2]}"
        echo "        \"worst time\": \"$s\"" >> "$JSON"
        printf "      }" >> "$JSON"
      fi
      if [ "${array_severity_wall[i0_sensor]}" -gt 0 ]; then
        if $first; then
          first=false
        else
          echo "," >> "$JSON"
        fi
        echo "      \"radiant asymmetry (wall)\": {" >> "$JSON"
        echo "        \"frequency of occurrence (%)\": \"${array_PTD_wall[i0_sensor]}\"," >> "$JSON"
        x="$(awk -v zoneName=$zone_name -v sensorName=$sensor_name -f "$script_dir/get_sensorStats.awk" "$tmp_dir/wall_summary")"
        a=($x)
        s="${a[0]}/${a[1]}/$year @ ${a[2]}"
        echo "        \"worst time\": \"$s\"" >> "$JSON"
        printf "      }" >> "$JSON"
      fi
      if $is_CFDandMRT; then
        if [ "${array_CFD_domains[i0_zone]}" -gt 0 ]; then
          if [ "${array_severity_draught[i0_sensor]}" -gt 0 ]; then
            if $first; then
              first=false
            else
              echo "," >> "$JSON"
            fi
            echo "      \"draught\": {" >> "$JSON"
            echo "        \"frequency of occurrence (%)\": \"${array_PTD_draught[i0_sensor]}\"," >> "$JSON"
            x="$(awk -v zoneName=$zone_name -v sensorName=$sensor_name -f "$script_dir/get_sensorStats.awk" "$tmp_dir/draught_summary")"
            a=($x)
            s="${a[0]}/${a[1]}/$year @ ${a[2]}"
            echo "        \"worst time\": \"$s\"" >> "$JSON"
            printf "      }" >> "$JSON"
          fi
          if [ "${array_severity_vertdT[i0_sensor]}" -gt 0 ]; then
            if $first; then
              first=false
            else
              echo "," >> "$JSON"
            fi
            echo "      \"vertical air temperature difference\": {" >> "$JSON"
            echo "        \"frequency of occurrence (%)\": \"${array_PTD_vertdT[i0_sensor]}\"," >> "$JSON"
            x="$(awk -v zoneName=$zone_name -v sensorName=$sensor_name -f "$script_dir/get_sensorStats.awk" "$tmp_dir/vertdT_summary")"
            a=($x)
            s="${a[0]}/${a[1]}/$year @ ${a[2]}"
            echo "        \"worst time\": \"$s\"" >> "$JSON"
            printf "      }" >> "$JSON"
          fi
        fi
      fi
      if [ "$simPeriod_days" -gt 1 ]; then
        if [ "${array_severity_optDD[i0_sensor]}" -gt 0 ]; then
          if $first; then
            first=false
          else
            echo "," >> "$JSON"
          fi
          echo "      \"daily temperature drift\": {" >> "$JSON"
          echo "        \"frequency of occurrence (%)\": \"${array_PTD_optDD[i0_sensor]}\"," >> "$JSON"
          JD2DM "$((array_DWD_optDD[i0_sensor]-1))"
          s="${dayMonth% *}/${dayMonth#* }/${year}"
          JD2DM "${array_DWD_optDD[i0_sensor]}"
          s2="$s - ${dayMonth% *}/${dayMonth#* }/${year}"
          echo "        \"worst time\": \"$s2\"" >> "$JSON"
          printf "      }" >> "$JSON"
        fi
      fi
      if [ "$simPeriod_days" -ge 7 ]; then
        if [ "${array_severity_optWD[i0_sensor]}" -gt 0 ]; then
          if $first; then
            first=false
          else
            echo "," >> "$JSON"
          fi
          echo "      \"weekly temperature drift\": {" >> "$JSON"
          echo "        \"frequency of occurrence (%)\": \"${array_PTD_optWD[i0_sensor]}\"," >> "$JSON"
          JD2DM "$((array_DWD_optWD[i0_sensor]-6))"
          s="${dayMonth% *}/${dayMonth#* }/${year}"
          JD2DM "${array_DWD_optWD[i0_sensor]}"
          s2="$s - ${dayMonth% *}/${dayMonth#* }/${year}"
          echo "        \"worst time\": \"$s2\"" >> "$JSON"
          printf "      }" >> "$JSON"
        fi
      fi
      echo '' >> "$JSON"
      printf '    }' >> "$JSON"
    fi
  done
  echo '' >> "$JSON"
  echo '  ],' >> "$JSON"
fi
echo '  "report": "",' >> "$JSON"
echo '  "results libraries": ""' >> "$JSON"
echo '}' >> "$JSON"

# Check json file exists.
if ! [ -f "$JSON" ]; then
  echo "Error: failed to write json output." >&2
  exit 110
fi



# Update progress file.
echo '8' > "$tmp_dir/progress.txt"

# *** Write report - latex ***
echo '\nonstopmode' > "$report"
echo '\documentclass[a4paper,11pt]{report}' >> "$report"
echo >> "$report"
echo '\usepackage[tmargin=2cm,bmargin=2cm,lmargin=2cm,rmargin=2cm]{geometry}' >> "$report"
echo '\usepackage{fontspec}' >> "$report"
echo '\setmainfont{TeX Gyre Termes}' >> "$report"
echo '\usepackage{underscore}' >> "$report"
echo '\usepackage{multirow}' >> "$report"
echo '\usepackage{scrextend}' >> "$report"
echo '\usepackage{lscape}' >> "$report"
echo '\usepackage{longtable}' >> "$report"
echo '\usepackage{booktabs}' >> "$report"
echo '\setlength{\parindent}{0cm}' >> "$report"
echo '\pagestyle{empty}' >>"$report"
echo >> "$report"

echo '\newcommand{\veryshortarrow}[1][3pt]{\mathrel{' >> "$report"
echo '   \hbox{\rule[\dimexpr\fontdimen22\textfont2-.2pt\relax]{#1}{.4pt}}' >> "$report"
echo '   \mkern-4mu\hbox{\usefont{U}{lasy}{m}{n}\symbol{41}}}}' >> "$report"
echo '\makeatletter' >> "$report"

echo '\begin{document}' >> "$report"
echo '\begin{landscape}' >> "$report"

if "$do_detailed_report"; then
  echo '\nonstopmode' > "$detailed_report"
  echo '\documentclass[a4paper,11pt]{report}' >> "$detailed_report"
  echo >> "$detailed_report"
  echo '\usepackage[tmargin=2cm,bmargin=2cm,lmargin=2cm,rmargin=2cm]{geometry}' >> "$detailed_report"
  echo '\usepackage{fontspec}' >> "$detailed_report"
  echo '\setmainfont{TeX Gyre Termes}' >> "$detailed_report"
  echo '\usepackage{underscore}' >> "$detailed_report"
  echo '\usepackage{multirow}' >> "$detailed_report"
  echo '\usepackage{scrextend}' >> "$detailed_report"
  echo '\usepackage{lscape}' >> "$detailed_report"
  echo '\usepackage{longtable}' >> "$detailed_report"
  echo '\usepackage{booktabs}' >> "$detailed_report"
  echo '\usepackage{pgfplots}' >> "$detailed_report"
  echo '\usepackage{siunitx}' >> "$detailed_report"
  echo '\usetikzlibrary{plotmarks}' >> "$detailed_report"
#  echo '\usepgfplotslibrary{external}' >> "$detailed_report"
#  echo '\tikzexternalize' >> "$detailed_report"
  echo '\setlength{\parindent}{0cm}' >> "$detailed_report"
  echo '\pagestyle{empty}' >>"$detailed_report"
  echo >> "$detailed_report"
  echo '\begin{document}' >> "$detailed_report"
  echo '\begin{landscape}' >> "$detailed_report"

  echo '\newcommand{\veryshortarrow}[1][3pt]{\mathrel{' >> "$detailed_report"
  echo '   \hbox{\rule[\dimexpr\fontdimen22\textfont2-.2pt\relax]{#1}{.4pt}}' >> "$detailed_report"
  echo '   \mkern-4mu\hbox{\usefont{U}{lasy}{m}{n}\symbol{41}}}}' >> "$detailed_report"
  echo '\makeatletter' >> "$detailed_report"
fi

# Title
echo '\begin{Large}' >> "$report"
echo 'Hit2gap BEMServer \\' >> "$report"
echo 'ESP-r module analysis report \\' >> "$report"
echo '\end{Large}' >> "$report"
echo '' >> "$report"

if "$do_detailed_report"; then
  echo '\begin{Large}' >> "$detailed_report"
  echo 'Hit2gap BEMServer \\' >> "$detailed_report"
  echo 'ESP-r module extended analysis report \\' >> "$detailed_report"
  echo '\end{Large}' >> "$detailed_report"
  echo '' >> "$detailed_report"
fi

# Preamble (analysis parameters).
if ! [ "X$preamble_file" == "X" ]; then
  cat "$preamble_file" >> "$report"
  echo '' >> "$report"

  if "$do_detailed_report"; then
    cat "$preamble_file" >> "$detailed_report"
    echo '' >> "$detailed_report"
  fi
fi

# Diagnosis (analysis outcomes)
echo 'Analysis outcomes' >> "$report"
echo '\begin{addmargin}[0.5cm]{0cm}' >> "$report"

if "$do_detailed_report"; then
  echo 'Analysis outcomes' >> "$detailed_report"
  echo '\begin{addmargin}[0.5cm]{0cm}' >> "$detailed_report"
fi

if [ "$performance_flag" -gt 0 ]; then
  echo 'Rank-ordered (by operative temperature) assessment results for locations that do not comply with the standard.' >> "$report"
  echo ' \\' >> "$report"
  echo '' >> "$report"
  echo '\setlength\LTleft{0.5cm}' >> "$report"
  echo '\setlength\LTright\fill' >> "$report"
  echo '\setlength\LTpre{0cm}' >> "$report"
  echo '\setlength\LTpost{0cm}' >> "$report"

  if "$do_detailed_report"; then
    echo 'The table lists rank-ordered (by operative temperature) assessment results for locations that do not comply with the standard.' >> "$detailed_report"
    echo 'Next, comfort parameter values at locations that do not comply with the standard are shown, with criteria from the standard as dashed lines.' >> "$detailed_report"
    if "$is_optDD_discomfort" || "$is_optWD_discomfort"; then
      echo 'The final figure shows daily mean operative temperature, with daily and weekly drift that violates the standard highlighted with dashed lines.' >> "$detailed_report"
    fi    
    echo ' \\' >> "$detailed_report"
    echo '' >> "$detailed_report"
    echo '\setlength\LTleft{0.5cm}' >> "$detailed_report"
    echo '\setlength\LTright\fill' >> "$detailed_report"
    echo '\setlength\LTpre{0cm}' >> "$detailed_report"
    echo '\setlength\LTpost{0cm}' >> "$detailed_report"
  fi

  # Table for all comfort metrics.
  echo '\begin{longtable}{l l p{2cm} p{2cm} p{2cm} p{2cm} p{2cm} p{2cm} p{2cm} p{2cm}}' >> "$report"
  echo '' >> "$report"
  echo '\hline' >> "$report"
  echo '\multirow{3}{*}{Area} & \multirow{3}{*}{Location} & \multirow{3}{2cm}{\centering{Operative\\temperature}} & \multirow{3}{2cm}{\centering{Floor\\temperature}} & \multirow{3}{2cm}{\centering{Radiant\\asymmetry\\(ceiling)}} & \multirow{3}{2cm}{\centering{Radiant\\asymmetry\\(wall)}} & \multirow{3}{2cm}{\centering{Draught}} & \multirow{3}{2cm}{\centering{Vertical air\\temperature\\difference}} & \multirow{3}{2cm}{\centering{Daily\\temperature\\drift}} & \multirow{3}{2cm}{\centering{Weekly\\temperature\\drift}} \\' >> "$report"
  echo ' \\' >> "$report"
  echo ' \\' >> "$report"
  echo '\hline' >> "$report"
  echo ' & & \multicolumn{8}{c}{\multirow{2}{12cm}{\centering{Frequency of violation of the criteria associated with the metrics above\\(\%)}}} \\' >> "$report"
  echo ' \\' >> "$report"
  echo '\cline{3-10}' >> "$report"
  echo '\endfirsthead' >> "$report"
  echo '' >> "$report"
  echo '\hline' >> "$report"
  echo '\multicolumn{10}{l}{\small\sl continued from previous page} \\' >> "$report"
  echo '\hline' >> "$report"
  echo '\multirow{3}{*}{Area} & \multirow{3}{*}{Location} & \multirow{3}{2cm}{\centering{Operative\\temperature}} & \multirow{3}{2cm}{\centering{Floor\\temperature}} & \multirow{3}{2cm}{\centering{Radiant\\asymmetry\\(ceiling)}} & \multirow{3}{2cm}{\centering{Radiant\\asymmetry\\(wall)}} & \multirow{3}{2cm}{\centering{Draught}} & \multirow{3}{2cm}{\centering{Vertical air\\temperature\\difference}} & \multirow{3}{2cm}{\centering{Daily\\temperature\\drift}} & \multirow{3}{2cm}{\centering{Weekly\\temperature\\drift}} \\' >> "$report"
  echo ' \\' >> "$report"
  echo ' \\' >> "$report"
  echo '\hline' >> "$report"
  echo ' & & \multicolumn{8}{c}{\multirow{2}{12cm}{\centering{Frequency of violation of the criteria associated with the metrics above\\(\%)}}} \\' >> "$report"
  echo ' \\' >> "$report"
  echo '\cline{3-10}' >> "$report"
  echo '\endhead' >> "$report"
  echo '' >> "$report"
  echo '\hline' >> "$report"
  echo '\multicolumn{10}{r}{\small\sl continued on next page} \\' >> "$report"
  echo '\hline' >> "$report"
  echo '\endfoot' >> "$report"
  echo '' >> "$report"
  echo '\endlastfoot' >> "$report"
  echo '' >> "$report"

  if "$do_detailed_report"; then
    echo '\begin{longtable}{l l p{2cm} p{2cm} p{2cm} p{2cm} p{2cm} p{2cm} p{2cm} p{2cm}}' >> "$detailed_report"
    echo '' >> "$detailed_report"
    echo '\hline' >> "$detailed_report"
    echo '\multirow{3}{*}{Area} & \multirow{3}{*}{Location} & \multirow{3}{2cm}{\centering{Operative\\temperature}} & \multirow{3}{2cm}{\centering{Floor\\temperature}} & \multirow{3}{2cm}{\centering{Radiant\\asymmetry\\(ceiling)}} & \multirow{3}{2cm}{\centering{Radiant\\asymmetry\\(wall)}} & \multirow{3}{2cm}{\centering{Draught}} & \multirow{3}{2cm}{\centering{Vertical air\\temperature\\difference}} & \multirow{3}{2cm}{\centering{Daily\\temperature\\drift}} & \multirow{3}{2cm}{\centering{Weekly\\temperature\\drift}} \\' >> "$detailed_report"
    echo ' \\' >> "$detailed_report"
    echo ' \\' >> "$detailed_report"
    echo '\hline' >> "$detailed_report"
    echo ' & & \multicolumn{8}{c}{\multirow{2}{12cm}{\centering{Frequency of violation of the criteria associated with the metrics above\\(\%)}}} \\' >> "$detailed_report"
    echo ' \\' >> "$detailed_report"
    echo '\cline{3-10}' >> "$detailed_report"
    echo '\endfirsthead' >> "$detailed_report"
    echo '' >> "$detailed_report"
    echo '\hline' >> "$detailed_report"
    echo '\multicolumn{10}{l}{\small\sl continued from previous page} \\' >> "$detailed_report"
    echo '\hline' >> "$detailed_report"
    echo '\multirow{3}{*}{Area} & \multirow{3}{*}{Location} & \multirow{3}{2cm}{\centering{Operative\\temperature}} & \multirow{3}{2cm}{\centering{Floor\\temperature}} & \multirow{3}{2cm}{\centering{Radiant\\asymmetry\\(ceiling)}} & \multirow{3}{2cm}{\centering{Radiant\\asymmetry\\(wall)}} & \multirow{3}{2cm}{\centering{Draught}} & \multirow{3}{2cm}{\centering{Vertical air\\temperature\\difference}} & \multirow{3}{2cm}{\centering{Daily\\temperature\\drift}} & \multirow{3}{2cm}{\centering{Weekly\\temperature\\drift}} \\' >> "$detailed_report"
    echo ' \\' >> "$detailed_report"
    echo ' \\' >> "$detailed_report"
    echo '\hline' >> "$detailed_report"
    echo ' & & \multicolumn{8}{c}{\multirow{2}{12cm}{\centering{Frequency of violation of the criteria associated with the metrics above\\(\%)}}} \\' >> "$detailed_report"
    echo ' \\' >> "$detailed_report"
    echo '\cline{3-10}' >> "$detailed_report"
    echo '\endhead' >> "$detailed_report"
    echo '' >> "$detailed_report"
    echo '\hline' >> "$detailed_report"
    echo '\multicolumn{10}{r}{\small\sl continued on next page} \\' >> "$detailed_report"
    echo '\hline' >> "$detailed_report"
    echo '\endfoot' >> "$detailed_report"
    echo '' >> "$detailed_report"
    echo '\endlastfoot' >> "$detailed_report"
    echo '' >> "$detailed_report"
  fi

  rm "$tmp_dir/PTD_table" 1>/dev/null 2>&1
#  s='\n\\end{longtable}\n\n\\begin{longtable}{l l p{2cm} p{2cm} p{2cm} p{2cm} p{2cm} p{2cm}}\n\n\\cline{3-8}\n\\phantom{Area} \& \\phantom{Location} \& \\multicolumn{6}{c}{\\multirow{2}{12cm}{\\centering{Time of worst violation of the criteria associated with the metrics above\\\\(MM-DD HH:MM)}}} \\\\\n \\\\\n\\cline{3-8}\n\\endfirsthead\n\n\\hline\n\\multicolumn{8}{l}{\\small\\sl continued from previous page} \\\\\n\\hline\n\\multirow{3}{*}{Area} \& \\multirow{3}{*}{Location} \& \\multirow{3}{1.9cm}{\\centering{Operative\\\\temperature}} \& \\multirow{3}{1.9cm}{\\centering{Floor\\\\temperature}} \& \\multirow{3}{1.8cm}{\\centering{Radiant\\\\asymmetry\\\\(ceiling)}} \& \\multirow{3}{1.8cm}{\\centering{Radiant\\\\asymmetry\\\\(wall)}} \& \\multirow{3}{1.6cm}{\\centering{Draught}} \& \\multirow{3}{1.9cm}{\\centering{Vertical air\\\\temperature\\\\difference}} \\\\\n \\\\\n \\\\\n\\hline\n\\phantom{Area} \& \\phantom{Location} \& \\multicolumn{6}{c}{\\multirow{2}{12cm}{\\centering{Time of worst violation of the criteria associated with the metrics above\\\\(MM-DD HH:MM)}}} \\\\\n \\\\\n\\cline{3-8}\n\\endhead\n\n\\hline\n\\multicolumn{8}{r}{\\small\\sl continued on next page} \\\\\n\\hline\n\\endfoot\n\n\\hline\n\\endlastfoot\n\n'

# Rank order table entries.
  j=1
  i0_CFDsen=-1
  for i0_sensor in "${array_sensor_indices[@]}"; do
    i0_zone="$((array_sensor_zones[i0_sensor]-1))"
    zone_name="${array_zone_names[i0_zone]}"
    num_sen="${array_MRT_sensors[i0_zone]}"
    sensor_name="${array_MRTsensor_names[i0_sensor]}"    
    severity_tmp=${array_sensor_severity[i0_sensor]}   
    if [ "$severity_tmp" -gt 0 ]; then
      if [ "${array_severity_opt[i0_sensor]}" -lt 0 ]; then
        PTD_opt='n/a'
      else
        PTD_opt="${array_PTD_opt[i0_sensor]}"
      fi
      if [ "${array_severity_floor[i0_zone]}" -lt 0 ]; then
        PTD_floor='n/a'
      else
        PTD_floor="${array_PTD_floor[i0_zone]}"
      fi
      if [ "${array_severity_ceiling[i0_sensor]}" -lt 0 ]; then
        PTD_ceiling='n/a'
      else
        PTD_ceiling="${array_PTD_ceiling[i0_sensor]}"
      fi
      if [ "${array_severity_wall[i0_sensor]}" -lt 0 ]; then
        PTD_wall='n/a'
      else
        PTD_wall="${array_PTD_wall[i0_sensor]}"
      fi
      if [ "$simPeriod_days" -gt 1 ]; then
        if [ "${array_severity_optDD[i0_sensor]}" -lt 0 ]; then
          PTD_optDD='n/a'
        else
          PTD_optDD="${array_PTD_optDD[i0_sensor]}"
        fi
      else
        PTD_optDD='n/a'
      fi
      if [ "$simPeriod_days" -ge 7 ]; then
        if [ "${array_severity_optWD[i0_sensor]}" -lt 0 ]; then
          PTD_optWD='n/a'
        else
          PTD_optWD="${array_PTD_optWD[i0_sensor]}"
        fi
      else
        PTD_optWD='n/a'
      fi
      if $is_CFD; then
        if [ "${array_CFD_domains[i0_zone]}" -gt 1 ]; then
          ((i0_CFDsen++))
          if [ "${array_severity_vertdT[i0_CFDsen]}" -lt 0 ]; then
            PTD_vertdT='n/a'
          else
            PTD_vertdT="${array_PTD_vertdT[i0_CFDsen]}"
          fi
          if [ "${array_severity_draught[i0_CFDsen]}" -lt 0 ]; then
            PTD_draught='n/a'
          else
            PTD_draught="${array_PTD_draught[i0_CFDsen]}"
          fi
        else
          PTD_vertdT='n/a'
          PTD_draught='n/a'
        fi
        echo "$zone_name & $sensor_name & \\hfil $PTD_opt & \\hfil $PTD_floor & \\hfil $PTD_ceiling & \\hfil $PTD_wall & \\hfil $PTD_draught & \\hfil $PTD_vertdT & \\hfil $PTD_optDD & \\hfil $PTD_optWD "'\\' >> "$tmp_dir/PTD_table"
      else
        echo "$zone_name & $sensor_name & \\hfil $PTD_opt & \\hfil $PTD_floor & \\hfil $PTD_ceiling & \\hfil $PTD_wall & \\hfil n/a & \\hfil n/a & \\hfil $PTD_optDD & \\hfil $PTD_optWD "'\\' >> "$tmp_dir/PTD_table"
      fi
    fi
    if [ $j -eq $num_sen ]; then
      j=1
    else
      ((j++))
    fi
  done
  echo '' >> "$tmp_dir/PTD_table"
  j=1
  i0_zone=-1
  i1_floor=0
  i0_CFDsen=-1
  for i0_sensor in "${array_sensor_indices[@]}"; do
    i0_zone_prev="$i0_zone"
    i0_zone="$((array_sensor_zones[i0_sensor]-1))"
    if [ "$i0_zone" -gt "$i0_zone_prev" ]; then ((i1_floor++)); fi
    zone_name="${array_zone_names[i0_zone]}"
    num_sen="${array_MRT_sensors[i0_zone]}"
    sensor_name="${array_MRTsensor_names[i0_sensor]}"    
    severity_tmp=${array_sensor_severity[i0_sensor]}   
    if [ "$severity_tmp" -gt 0 ]; then
      if [ "${array_PTD_opt[i0_sensor]}" == "0.0" ] || [ "${array_severity_opt[i0_sensor]}" -lt 0 ]; then
        opt_worstTime='n/a'
      else
        s="$(awk -v zoneName=$zone_name -v sensorName=$sensor_name -f "$script_dir/get_sensorStats.awk" "$tmp_dir/all_opt_summary")"
        a=($s)
        opt_worstTime="$(printf "%02d" "${a[1]}")-${a[0]} ${a[2]}"
      fi
      if [ "${array_PTD_floor[i0_zone]}" == "0.0" ] || [ "${array_severity_floor[i0_zone]}" -lt 0 ]; then
        floor_worstTime='n/a'
      else
        s="$(awk -v entryNum="$i1_floor" -f "$script_dir/get_sensorStats.awk" "$tmp_dir/floor_summary")"
        a=($s)
        floor_worstTime="$(printf "%02d" "${a[1]}")-${a[0]} ${a[2]}"
      fi
      if [ "${array_PTD_ceiling[i0_sensor]}" == "0.0" ] || [ "${array_severity_ceiling[i0_sensor]}" -lt 0 ]; then
        ceiling_worstTime='n/a'
      else
        s="$(awk -v zoneName=$zone_name -v sensorName=$sensor_name -f "$script_dir/get_sensorStats.awk" "$tmp_dir/ceiling_summary")"
        a=($s)
        ceiling_worstTime="$(printf "%02d" "${a[1]}")-${a[0]} ${a[2]}"
      fi
      if [ "${array_PTD_wall[i0_sensor]}" == "0.0" ] || [ "${array_severity_wall[i0_sensor]}" -lt 0 ]; then
        wall_worstTime='n/a'
      else
        s="$(awk -v zoneName=$zone_name -v sensorName=$sensor_name -f "$script_dir/get_sensorStats.awk" "$tmp_dir/wall_summary")"
        a=($s)
        wall_worstTime="$(printf "%02d" "${a[1]}")-${a[0]} ${a[2]}"
      fi
      if [ "$simPeriod_days" -gt 1 ]; then
        if [ "${array_PTD_optDD[i0_sensor]}" == "0.0" ] || [ "${array_severity_optDD[i0_sensor]}" -lt 0 ]; then
          optDD_worstTime='n/a'
        else
          JD2DM "$((array_DWD_optDD[i0_sensor]-1))"
          s="$(printf "%02d" "${dayMonth#* }")-$(printf "%02d" "${dayMonth% *}")"
          JD2DM "${array_DWD_optDD[i0_sensor]}"
          optDD_worstTime="$s\$\\veryshortarrow\$$(printf "%02d" "${dayMonth#* }")-$(printf "%02d" "${dayMonth% *}")"
        fi
      else
        optDD_worstTime='n/a'
      fi
      if [ "$simPeriod_days" -ge 7 ]; then
        if [ "${array_PTD_optWD[i0_sensor]}" == "0.0" ] || [ "${array_severity_optWD[i0_sensor]}" -lt 0 ]; then
          optWD_worstTime='n/a'
        else
          JD2DM "$((array_DWD_optWD[i0_sensor]-6))"
          s="$(printf "%02d" "${dayMonth#* }")-$(printf "%02d" "${dayMonth% *}")"
          JD2DM "${array_DWD_optWD[i0_sensor]}"
          optWD_worstTime="$s\$\\veryshortarrow\$$(printf "%02d" "${dayMonth#* }")-$(printf "%02d" "${dayMonth% *}")"
        fi
      else
        optWD_worstTime='n/a'
      fi
      if $is_CFD; then
        if [ "${array_CFD_domains[i0_zone]}" -gt 1 ]; then
          ((i0_CFDsen++))
          if [ "${array_PTD_draught[i0_CFDsen]}" == "0.0" ] || [ "${array_severity_draught[i0_CFDsen]}" -lt 0 ]; then
            draught_worstTime='n/a'
          else
            s="$(awk -v zoneName=$zone_name -v sensorName=$sensor_name -f "$script_dir/get_sensorStats.awk" "$tmp_dir/draught_summary")"
            a=($s)
            draught_worstTime="$(printf "%02d" "${a[1]}")-${a[0]} ${a[2]}"
          fi
          if [ "${array_PTD_vertdT[i0_CFDsen]}" == "0.0" ] || [ "${array_severity_vertdT[i0_CFDsen]}" -lt 0 ]; then
            vertdT_worstTime='n/a'
          else
            s="$(awk -v zoneName=$zone_name -v sensorName=$sensor_name -f "$script_dir/get_sensorStats.awk" "$tmp_dir/vertdT_summary")"
            a=($s)
            vertdT_worstTime="$(printf "%02d" "${a[1]}")-${a[0]} ${a[2]}"
          fi
          echo "$zone_name & $sensor_name & \\hfil $opt_worstTime & \\hfil $floor_worstTime & \\hfil $ceiling_worstTime & \\hfil $wall_worstTime & \\hfil $draught_worstTime & \\hfil $vertdT_worstTime & \\hfil $optDD_worstTime & \\hfil $optWD_worstTime "'\\' >> "$tmp_dir/PTD_table"
        else
          echo "$zone_name & $sensor_name & \\hfil $opt_worstTime & \\hfil $floor_worstTime & \\hfil $ceiling_worstTime & \\hfil $wall_worstTime & \\hfil n/a & \\hfil n/a & \\hfil $optDD_worstTime & \\hfil $optWD_worstTime "'\\' >> "$tmp_dir/PTD_table"
        fi
      else
        echo "$zone_name & $sensor_name & \\hfil $opt_worstTime & \\hfil $floor_worstTime & \\hfil $ceiling_worstTime & \\hfil $wall_worstTime & \\hfil n/a & \\hfil n/a & \\hfil $optDD_worstTime & \\hfil $optWD_worstTime "'\\' >> "$tmp_dir/PTD_table"
      fi
    fi
    if [ $j -eq $num_sen ]; then
      j=1
    else
      ((j++))
    fi
  done

  sorted="$(awk -f "$script_dir/sort_PTDtableEntries" "$tmp_dir/PTD_table")"
  echo "$sorted" > "$tmp_dir/sorted.trace"

# Replace keyword in awk output (between PTD and worst time) with latex magic.
  s='\n\\end{longtable}\n\n'
  s="$s"'\\begin{longtable}{l l p{2cm} p{2cm} p{2cm} p{2cm} p{2cm} p{2cm} p{2cm} p{2cm}}\n\n'
  s="$s"'\\cline{3-10}\n'
  s="$s"'\\phantom{Area} \& \\phantom{Location} \& \\multicolumn{8}{c}{\\centering{Time of worst violation of the criteria associated with the metrics above}} \\\\\n'
  s="$s"'\\phantom{Area} \& \\phantom{Location} \& \\multicolumn{6}{c}{\\centering{(MM-DD HH:MM)}} \& \\multicolumn{2}{c}{\\centering{(MM-DD\$\\veryshortarrow\$MM-DD)}} \\\\\n'
  s="$s"'\\cmidrule(r){3-8} \\cmidrule(l){9-10}\n'
  s="$s"'\\endfirsthead\n\n'
  s="$s"'\\hline\n'
  s="$s"'\\multicolumn{10}{l}{\\small\\sl continued from previous page} \\\\\n'
  s="$s"'\\hline\n'
  s="$s"'\\multirow{3}{*}{Area} \& \\multirow{3}{*}{Location} \& \\multirow{3}{2cm}{\\centering{Operative\\\\temperature}} \& \\multirow{3}{2cm}{\\centering{Floor\\\\temperature}} \& \\multirow{3}{2cm}{\\centering{Radiant\\\\asymmetry\\\\(ceiling)}} \& \\multirow{3}{2cm}{\\centering{Radiant\\\\asymmetry\\\\(wall)}} \& \\multirow{3}{2cm}{\\centering{Draught}} \& \\multirow{3}{2cm}{\\centering{Vertical air\\\\temperature\\\\difference}} \& \\multirow{3}{2cm}{\\centering{Daily\\\\temperature\\\\drift}} \& \\multirow{3}{2cm}{\\centering{Weekly\\\\temperature\\\\drift}} \\\\\n \\\\\n \\\\\n'
  s="$s"'\\hline\n'
  s="$s"'\\phantom{Area} \& \\phantom{Location} \& \\multicolumn{8}{c}{\\centering{Time of worst violation of the criteria associated with the metrics above}} \\\\\n'
  s="$s"'\\phantom{Area} \& \\phantom{Location} \& \\multicolumn{6}{c}{\\centering{(MM-DD HH:MM)}} \& \\multicolumn{2}{c}{\\centering{(MM-DD\$\\veryshortarrow\$MM-DD)}} \\\\\n'
  s="$s"'\\cmidrule(r){3-8} \\cmidrule(l){9-10}\n'
  s="$s"'\\endhead\n\n'
  s="$s"'\\hline\n\\multicolumn{10}{r}{\\small\\sl continued on next page} \\\\\n'
  s="$s"'\\hline\n'
  s="$s"'\\endfoot\n\n'
  s="$s"'\\hline\n'
  s="$s"'\\endlastfoot\n\n'
  #s='\n\\end{longtable}\n\n\\begin{longtable}{l l p{2cm} p{2cm} p{2cm} p{2cm} p{2cm} p{2cm}}\n\n\\cline{3-8}\n\\phantom{Area} \& \\phantom{Location} \& \\multicolumn{6}{c}{\\multirow{2}{12cm}{\\centering{Time of worst violation of the criteria associated with the metrics above\\\\(MM-DD HH:MM)}}} \\\\\n \\\\\n\\cline{3-8}\n\\endfirsthead\n\n\\hline\n\\multicolumn{8}{l}{\\small\\sl continued from previous page} \\\\\n\\hline\n\\multirow{3}{*}{Area} \& \\multirow{3}{*}{Location} \& \\multirow{3}{1.9cm}{\\centering{Operative\\\\temperature}} \& \\multirow{3}{1.9cm}{\\centering{Floor\\\\temperature}} \& \\multirow{3}{1.8cm}{\\centering{Radiant\\\\asymmetry\\\\(ceiling)}} \& \\multirow{3}{1.8cm}{\\centering{Radiant\\\\asymmetry\\\\(wall)}} \& \\multirow{3}{1.6cm}{\\centering{Draught}} \& \\multirow{3}{1.9cm}{\\centering{Vertical air\\\\temperature\\\\difference}} \\\\\n \\\\\n \\\\\n\\hline\n\\phantom{Area} \& \\phantom{Location} \& \\multicolumn{6}{c}{\\multirow{2}{12cm}{\\centering{Time of worst violation of the criteria associated with the metrics above\\\\(MM-DD HH:MM)}}} \\\\\n \\\\\n\\cline{3-8}\n\\endhead\n\n\\hline\n\\multicolumn{8}{r}{\\small\\sl continued on next page} \\\\\n\\hline\n\\endfoot\n\n\\hline\n\\endlastfoot\n\n'

  sorted_replaced="$(echo "$sorted" | sed -e 's/KW_REPLACEME/'"$s"'/')"
  echo "$sorted_replaced" > "$tmp_dir/sorted_replaced.trace"

  echo "$sorted_replaced" >> "$report"
  echo '\end{longtable}' >> "$report"

  if "$do_detailed_report"; then
    echo "$sorted_replaced" >> "$detailed_report"
    echo '\end{longtable}' >> "$detailed_report"
  fi

  if "$do_detailed_report"; then
    echo '' >> "$detailed_report"

  # How long are we simulating for?
    num_sim_days="$((simF_JD-simS_JD+1))"
    xmin=0

  # Set up lists of pfgplots colours and marks.
    array_pgfColours=('green' 'cyan' 'magenta' 'brown' 'lime' 'olive' 'orange' 'pink' 'purple' 'teal' 'violet')
    array_pgfMarks=('x' '+' '-' '|' 'o' 'star' '10-pointed star' 'oplus' 'otimes' 'square' 'triangle' 'diamond' 'Mercedes star' 'Mercedes star flipped' 'halfcircle' 'pentagon')
    
  # Operative temperature graph.
    if "$is_opt_discomfort"; then
      timebase="$(awk -f "$script_dir/get_timebase.awk" $opt_awk_input)"
      echo '\begin{figure}[h]' >> "$detailed_report"
      echo '\centering' >> "$detailed_report"
      echo '\begin{tikzpicture}' >> "$detailed_report"
      echo '\begin{axis}[' >> "$detailed_report"
      echo '/pgf/number format/1000 sep={ },' >> "$detailed_report"
      echo 'legend style= {at={(0.5,1.02)}, anchor=south },' >> "$detailed_report"
      echo 'legend columns = 5,' >> "$detailed_report"
      if [ $num_sim_days -gt 7 ]; then
        echo 'width=20cm,' >> "$detailed_report"
        echo 'height=10cm,' >> "$detailed_report"
        echo 'xlabel={Time (days)},' >> "$detailed_report"
        echo 'xmin={'"$xmin"'},' >> "$detailed_report"
        xmax="$num_sim_days"
        echo 'xmax={'"$xmax"'},' >> "$detailed_report"
      else
        echo 'width=20cm,' >> "$detailed_report"
        echo 'height=10cm,' >> "$detailed_report"
        echo 'xlabel={Time (hours)},' >> "$detailed_report"
        echo 'xmin={'"$xmin"'},' >> "$detailed_report"
        xmax=$((num_sim_days*24))
        echo 'xmax={'"$xmax"'},' >> "$detailed_report"
      fi
      echo 'ylabel={operative temperature (\si{\celsius})},' >> "$detailed_report"
      echo ']' >> "$detailed_report"

    # Loop over sensors with discomfort.
      i0_zone=-1
      i0_colour=-1
      legend=''
      for i0_sensor in "${array_sensor_indices[@]}"; do
        if [ "${array_severity_opt[i0_sensor]}" -gt 0 ]; then

    # Set colour by zone and mark by sensor.
          i0_zone_prev="$i0_zone"
          i0_zone="$((${array_sensor_zones[i0_sensor]}-1))"
          zone_name="${array_zone_names[i0_zone]}"
          sensor_name="${array_MRTsensor_names[i0_sensor]}"  
          if [ "$i0_zone" -gt "$i0_zone_prev" ]; then 
            ((i0_colour++))
            i0_mark=0
          else
            ((i0_mark++))
          fi

    # Add a plot for each occupied period.
          i=1
          while [ "$i" -le "${array_num_opt_plotFiles[i0_sensor]}" ]; do
            echo '\addplot['"color=${array_pgfColours[i0_colour]},mark=${array_pgfMarks[i0_mark]}"'] table [' >> "$detailed_report"
            if [ $num_sim_days -gt 7 ]; then
              echo 'x expr=(\thisrowno{0}-'"$timebase"'),' >> "$detailed_report"
            else
              echo 'x expr=(\thisrowno{0}-'"$timebase"')*24,' >> "$detailed_report"
            fi
            echo ']' >> "$detailed_report"
            echo '{'"$tmp_dir/sen$i0_sensor-opt-$i.txt"'};' >> "$detailed_report"
            if [ "$i" -eq 1 ]; then
              legend="${legend}${zone_name} ${sensor_name},"
              num_commas=-1
            else
              legend="${legend},"
              ((num_commas--))
            fi          
            ((i++))
          done
        fi
      done

    # Define operative temperature criteria lines coordinates.
      maxcoords=''
      mincoords=''

      # First, add starting point.
      if [ "$simS_JD" -le "$SpS_JD" ]; then
        maxcoords="$maxcoords ($xmin,$opt_criteria_max_win)"
        mincoords="$mincoords ($xmin,$opt_criteria_min_win)"
      elif [ "$simS_JD" -gt "$SpS_JD" ] && [ "$simS_JD" -lt "$SpF_JD" ]; then
        range_JD="$((SpF_JD-SpS_JD))"
        point_JD="$((simS_JD-SpS_JD))"
        range_criteria="$(echo "$opt_criteria_max_sum $opt_criteria_max_win" | awk '{print $1-$2}')"
        y="$(echo '' | awk -v range_JD="$range_JD" -v range_criteria="$range_criteria" -v point_JD="$point_JD" -v min_criteria="$opt_criteria_max_win" '{print min_criteria+point_JD*range_criteria/range_JD}')"
        maxcoords="$maxcoords ($xmin,$y)"
        range_criteria="$(echo "$opt_criteria_min_sum $opt_criteria_min_win" | awk '{print $1-$2}')"
        y="$(echo '' | awk -v range_JD="$range_JD" -v range_criteria="$range_criteria" -v point_JD="$point_JD" -v min_criteria="$opt_criteria_min_win" '{print min_criteria+point_JD*range_criteria/range_JD}')"
        mincoords="$mincoords ($xmin,$y)"
      elif [ "$simS_JD" -ge "$SuS_JD" ] && [ "$simS_JD" -le "$SuF_JD" ]; then
        maxcoords="$maxcoords ($xmin,$opt_criteria_max_sum)"
        mincoords="$mincoords ($xmin,$opt_criteria_min_sum)"
      elif [ "$simS_JD" -gt "$AS_JD" ] && [ "$simS_JD" -lt "$AF_JD" ]; then
        range_JD="$((AF_JD-AS_JD))"
        point_JD="$((simS_JD-AS_JD))"
        range_criteria="$(echo "$opt_criteria_max_win $opt_criteria_max_sum" | awk '{print $1-$2}')"
        y="$(echo '' | awk -v range_JD="$range_JD" -v range_criteria="$range_criteria" -v point_JD="$point_JD" -v min_criteria="$opt_criteria_max_sum" '{print min_criteria+point_JD*range_criteria/range_JD}')"
        maxcoords="$maxcoords ($xmin,$y)"
        range_criteria="$(echo "$opt_criteria_min_win $opt_criteria_min_sum" | awk '{print $1-$2}')"
        y="$(echo '' | awk -v range_JD="$range_JD" -v range_criteria="$range_criteria" -v point_JD="$point_JD" -v min_criteria="$opt_criteria_min_sum" '{print min_criteria+point_JD*range_criteria/range_JD}')"
        mincoords="$mincoords ($xmin,$y)"
      elif [ "$simS_JD" -ge "$AF_JD" ]; then
        maxcoords="$maxcoords ($xmin,$opt_criteria_max_win)"
        mincoords="$mincoords ($xmin,$opt_criteria_min_win)"
      fi

      # Next, add season start and end points if needed.
      if [ "$simS_JD" -lt "$SpS_JD" ] && [ "$simF_JD" -gt "$SpS_JD" ]; then
        x="$((SpS_JD-simS_JD))"
        maxcoords="$maxcoords ($x,$opt_criteria_max_win)"
        mincoords="$mincoords ($x,$opt_criteria_min_win)"
      fi
      if [ "$simS_JD" -lt "$SpF_JD" ] && [ "$simF_JD" -gt "$SpF_JD" ]; then
        x="$((SpF_JD-simS_JD))"
        maxcoords="$maxcoords ($x,$opt_criteria_max_sum)"
        mincoords="$mincoords ($x,$opt_criteria_min_sum)"
      fi
      if [ "$simS_JD" -lt "$AS_JD" ] && [ "$simF_JD" -gt "$AS_JD" ]; then
        x="$((AS_JD-simS_JD))"
        maxcoords="$maxcoords ($x,$opt_criteria_max_sum)"
        mincoords="$mincoords ($x,$opt_criteria_min_sum)"
      fi
      if [ "$simS_JD" -lt "$AF_JD" ] && [ "$simF_JD" -gt "$AF_JD" ]; then
        x="$((AF_JD-simS_JD))"
        maxcoords="$maxcoords ($x,$opt_criteria_max_win)"
        mincoords="$mincoords ($x,$opt_criteria_min_win)"
      fi

      # Finally, add finish point.
      if [ "$simF_JD" -le "$SpS_JD" ]; then
        maxcoords="$maxcoords ($xmax,$opt_criteria_max_win)"
        mincoords="$mincoords ($xmax,$opt_criteria_min_win)"
      elif [ "$simF_JD" -gt "$SpS_JD" ] && [ "$simF_JD" -lt "$SpF_JD" ]; then
        range_JD="$((SpF_JD-SpS_JD))"
        point_JD="$((simF_JD-SpS_JD))"
        range_criteria="$(echo "$opt_criteria_max_sum $opt_criteria_max_win" | awk '{print $1-$2}')"
        y="$(echo '' | awk -v range_JD="$range_JD" -v range_criteria="$range_criteria" -v point_JD="$point_JD" -v min_criteria="$opt_criteria_max_win" '{print min_criteria+point_JD*range_criteria/range_JD}')"
        maxcoords="$maxcoords ($xmax,$y)"
        range_criteria="$(echo "$opt_criteria_min_sum $opt_criteria_min_win" | awk '{print $1-$2}')"
        y="$(echo '' | awk -v range_JD="$range_JD" -v range_criteria="$range_criteria" -v point_JD="$point_JD" -v min_criteria="$opt_criteria_min_win" '{print min_criteria+point_JD*range_criteria/range_JD}')"
        mincoords="$mincoords ($xmax,$y)"
      elif [ "$simF_JD" -ge "$SuS_JD" ] && [ "$simF_JD" -le "$SuF_JD" ]; then
        maxcoords="$maxcoords ($xmax,$opt_criteria_max_sum)"
        mincoords="$mincoords ($xmax,$opt_criteria_min_sum)"
      elif [ "$simF_JD" -gt "$AS_JD" ] && [ "$simF_JD" -lt "$AF_JD" ]; then
        range_JD="$((AF_JD-AS_JD))"
        point_JD="$((simF_JD-AS_JD))"
        range_criteria="$(echo "$opt_criteria_max_win $opt_criteria_max_sum" | awk '{print $1-$2}')"
        y="$(echo '' | awk -v range_JD="$range_JD" -v range_criteria="$range_criteria" -v point_JD="$point_JD" -v min_criteria="$opt_criteria_max_sum" '{print min_criteria+point_JD*range_criteria/range_JD}')"
        maxcoords="$maxcoords ($xmax,$y)"
        range_criteria="$(echo "$opt_criteria_min_win $opt_criteria_min_sum" | awk '{print $1-$2}')"
        y="$(echo '' | awk -v range_JD="$range_JD" -v range_criteria="$range_criteria" -v point_JD="$point_JD" -v min_criteria="$opt_criteria_min_sum" '{print min_criteria+point_JD*range_criteria/range_JD}')"
        mincoords="$mincoords ($xmax,$y)"
      elif [ "$simF_JD" -ge "$AF_JD" ]; then
        maxcoords="$maxcoords ($xmax,$opt_criteria_max_win)"
        mincoords="$mincoords ($xmax,$opt_criteria_min_win)"
      fi

      echo '\addplot[red, dashed] coordinates {'"$maxcoords"'};' >> "$detailed_report"
      echo '\addplot[blue, dashed] coordinates {'"$mincoords"'};' >> "$detailed_report"

      echo '\legend{'"${legend:0:$num_commas}"'}' >> "$detailed_report"

      echo '\end{axis}' >> "$detailed_report"
      echo '\end{tikzpicture}' >> "$detailed_report"
      echo '\end{figure}' >> "$detailed_report"
      echo '' >> "$detailed_report"
    fi

    # Floor discomfort graph
    if "$is_floor_discomfort"; then
      timebase="$(awk -f "$script_dir/get_timebase.awk" "$tmp_dir/floor_discomfort")"
      echo '\begin{figure}[h]' >> "$detailed_report"
      echo '\centering' >> "$detailed_report"
      echo '\begin{tikzpicture}' >> "$detailed_report"
      echo '\begin{axis}[' >> "$detailed_report"
      echo '/pgf/number format/1000 sep={ },' >> "$detailed_report"
      echo 'legend style= {at={(0.5,1.02)}, anchor=south },' >> "$detailed_report"
      echo 'legend columns = 5,' >> "$detailed_report"
      if [ $num_sim_days -gt 7 ]; then
        echo 'width=20cm,' >> "$detailed_report"
        echo 'height=10cm,' >> "$detailed_report"
        echo 'xlabel={Time (days)},' >> "$detailed_report"
        echo 'xmin={'"$xmin"'},' >> "$detailed_report"
        xmax="$num_sim_days"
        echo 'xmax={'"$xmax"'},' >> "$detailed_report"
      else
        echo 'width=20cm,' >> "$detailed_report"
        echo 'height=10cm,' >> "$detailed_report"
        echo 'xlabel={Time (hours)},' >> "$detailed_report"
        echo 'xmin={'"$xmin"'},' >> "$detailed_report"
        xmax=$((num_sim_days*24))
        echo 'xmax={'"$xmax"'},' >> "$detailed_report"
      fi
      echo 'ylabel={discomfort due to floor temperature (\%)},' >> "$detailed_report"
      echo ']' >> "$detailed_report"

      # Loop over zones with discomfort.
      i0_colour=-1
      legend=''
      for i0_zone in "${array_zone_indices[@]}"; do
        if [ "${array_num_floor_surfaces[i0_zone]}" -gt 0 ]; then
          if [ "${array_severity_floor[i0_zone]}" -gt 0 ]; then

            # Set colour by zone.
            ((i0_colour++))
            zone_name="${array_zone_names[i0_zone]}"

            # Add a plot for each occupied period.
            i=1

            while [ "$i" -le "${array_num_floor_plotFiles[i0_zone]}" ]; do
              echo '\addplot['"color=${array_pgfColours[i0_colour]},mark=${array_pgfMarks[0]}"'] table [' >> "$detailed_report"
              if [ $num_sim_days -gt 7 ]; then
                echo 'x expr=(\thisrowno{0}-'"$timebase"'),' >> "$detailed_report"
              else
                echo 'x expr=(\thisrowno{0}-'"$timebase"')*24,' >> "$detailed_report"
              fi
              echo ']' >> "$detailed_report"
              echo '{'"$tmp_dir/zon$i0_zone-floor-$i.txt"'};' >> "$detailed_report"
              if [ "$i" -eq 1 ]; then
                legend="${legend}${zone_name},"
                num_commas=-1
              else
                legend="${legend},"
                ((num_commas--))
              fi          
              ((i++))
            done
          fi
        fi
      done

      # Define floor discomfort criteria line.
      echo '\addplot[black, dashed, samples=2, domain='"$xmin:$xmax"'] {'"$floor_criteria"'};' >> "$detailed_report"

      echo '\legend{'"${legend:0:$num_commas}"'}' >> "$detailed_report"

      echo '\end{axis}' >> "$detailed_report"
      echo '\end{tikzpicture}' >> "$detailed_report"
      echo '\end{figure}' >> "$detailed_report"
      echo '' >> "$detailed_report"
    fi

    # Ceiling discomfort graph.
    if "$is_ceiling_discomfort"; then
      timebase="$(awk -f "$script_dir/get_timebase.awk" "$tmp_dir/ceiling_discomfort")"
      echo '\begin{figure}[h]' >> "$detailed_report"
      echo '\centering' >> "$detailed_report"
      echo '\begin{tikzpicture}' >> "$detailed_report"
      echo '\begin{axis}[' >> "$detailed_report"
      echo '/pgf/number format/1000 sep={ },' >> "$detailed_report"
      echo 'legend style= {at={(0.5,1.02)}, anchor=south },' >> "$detailed_report"
      echo 'legend columns = 5,' >> "$detailed_report"
      if [ $num_sim_days -gt 7 ]; then
        echo 'width=20cm,' >> "$detailed_report"
        echo 'height=10cm,' >> "$detailed_report"
        echo 'xlabel={Time (days)},' >> "$detailed_report"
        echo 'xmin={'"$xmin"'},' >> "$detailed_report"
        xmax="$num_sim_days"
        echo 'xmax={'"$xmax"'},' >> "$detailed_report"
      else
        echo 'width=20cm,' >> "$detailed_report"
        echo 'height=10cm,' >> "$detailed_report"
        echo 'xlabel={Time (hours)},' >> "$detailed_report"
        echo 'xmin={'"$xmin"'},' >> "$detailed_report"
        xmax=$((num_sim_days*24))
        echo 'xmax={'"$xmax"'},' >> "$detailed_report"
      fi
      echo 'ylabel={discomfort due to ceiling temperature (\%)},' >> "$detailed_report"
      echo ']' >> "$detailed_report"

      # Loop over sensors with discomfort.
      i0_zone=-1
      i0_colour=-1
      legend=''
      for i0_sensor in "${array_sensor_indices[@]}"; do
        if [ "${array_severity_ceiling[i0_sensor]}" -gt 0 ]; then

          # Set colour by zone and mark by sensor.
          i0_zone_prev="$i0_zone"
          i0_zone="$((array_sensor_zones[i0_sensor]-1))"
          zone_name="${array_zone_names[i0_zone]}"
          sensor_name="${array_MRTsensor_names[i0_sensor]}"  
          if [ "$i0_zone" -gt "$i0_zone_prev" ]; then 
            ((i0_colour++))
            i0_mark=0
          else
            ((i0_mark++))
          fi

          # Add a plot for each occupied period.
          i=1
          while [ "$i" -le "${array_num_ceil_plotFiles[i0_sensor]}" ]; do
            echo '\addplot['"color=${array_pgfColours[i0_colour]},mark=${array_pgfMarks[i0_mark]}"'] table [' >> "$detailed_report"
            if [ $num_sim_days -gt 7 ]; then
              echo 'x expr=(\thisrowno{0}-'"$timebase"'),' >> "$detailed_report"
            else
              echo 'x expr=(\thisrowno{0}-'"$timebase"')*24,' >> "$detailed_report"
            fi
            echo ']' >> "$detailed_report"
            echo '{'"$tmp_dir/sen$i0_sensor-ceil-$i.txt"'};' >> "$detailed_report"
            if [ "$i" -eq 1 ]; then
              legend="${legend}${zone_name} ${sensor_name},"
              num_commas=-1
            else
              legend="${legend},"
              ((num_commas--))
            fi          
            ((i++))
          done
        fi
      done

      # Define discomfort criteria line.
      echo '\addplot[black, dashed, samples=2, domain='"$xmin:$xmax"'] {'"$asym_criteria"'};' >> "$detailed_report"

      echo '\legend{'"${legend:0:$num_commas}"'}' >> "$detailed_report"

      echo '\end{axis}' >> "$detailed_report"
      echo '\end{tikzpicture}' >> "$detailed_report"
      echo '\end{figure}' >> "$detailed_report"
      echo '' >> "$detailed_report"
    fi

    # Wall discomfort graph.
    if "$is_wall_discomfort"; then
      timebase="$(awk -f "$script_dir/get_timebase.awk" "$tmp_dir/wall_discomfort")"
      echo '\begin{figure}[h]' >> "$detailed_report"
      echo '\centering' >> "$detailed_report"
      echo '\begin{tikzpicture}' >> "$detailed_report"
      echo '\begin{axis}[' >> "$detailed_report"
      echo '/pgf/number format/1000 sep={ },' >> "$detailed_report"
      echo 'legend style= {at={(0.5,1.02)}, anchor=south },' >> "$detailed_report"
      echo 'legend columns = 5,' >> "$detailed_report"
      if [ $num_sim_days -gt 7 ]; then
        echo 'width=20cm,' >> "$detailed_report"
        echo 'height=10cm,' >> "$detailed_report"
        echo 'xlabel={Time (days)},' >> "$detailed_report"
        echo 'xmin={'"$xmin"'},' >> "$detailed_report"
        xmax="$num_sim_days"
        echo 'xmax={'"$xmax"'},' >> "$detailed_report"
      else
        echo 'width=20cm,' >> "$detailed_report"
        echo 'height=10cm,' >> "$detailed_report"
        echo 'xlabel={Time (hours)},' >> "$detailed_report"
        echo 'xmin={'"$xmin"'},' >> "$detailed_report"
        xmax=$((num_sim_days*24))
        echo 'xmax={'"$xmax"'},' >> "$detailed_report"
      fi
      echo 'ylabel={discomfort due to wall temperatures (\%)},' >> "$detailed_report"
      echo ']' >> "$detailed_report"

      # Loop over sensors with discomfort.
      i0_zone=-1
      i0_colour=-1
      legend=''
      for i0_sensor in "${array_sensor_indices[@]}"; do
        if [ "${array_severity_wall[i0_sensor]}" -gt 0 ]; then

          # Set colour by zone and mark by sensor.
          i0_zone_prev="$i0_zone"
          i0_zone="$((array_sensor_zones[i0_sensor]-1))"
          zone_name="${array_zone_names[i0_zone]}"
          sensor_name="${array_MRTsensor_names[i0_sensor]}"  
          if [ "$i0_zone" -gt "$i0_zone_prev" ]; then 
            ((i0_colour++))
            i0_mark=0
          else
            ((i0_mark++))
          fi

          # Add a plot for each occupied period.
          i=1
          while [ "$i" -le "${array_num_wall_plotFiles[i0_sensor]}" ]; do
            echo '\addplot['"color=${array_pgfColours[i0_colour]},mark=${array_pgfMarks[i0_mark]}"'] table [' >> "$detailed_report"
            if [ $num_sim_days -gt 7 ]; then
              echo 'x expr=(\thisrowno{0}-'"$timebase"'),' >> "$detailed_report"
            else
              echo 'x expr=(\thisrowno{0}-'"$timebase"')*24,' >> "$detailed_report"
            fi
            echo ']' >> "$detailed_report"
            echo '{'"$tmp_dir/sen$i0_sensor-wall-$i.txt"'};' >> "$detailed_report"
            if [ "$i" -eq 1 ]; then
              legend="${legend}${zone_name} ${sensor_name},"
              num_commas=-1
            else
              legend="${legend},"
              ((num_commas--))
            fi          
            ((i++))
          done
        fi
      done

      # Define discomfort criteria line.
      echo '\addplot[black, dashed, samples=2, domain='"$xmin:$xmax"'] {'"$asym_criteria"'};' >> "$detailed_report"

      echo '\legend{'"${legend:0:$num_commas}"'}' >> "$detailed_report"

      echo '\end{axis}' >> "$detailed_report"
      echo '\end{tikzpicture}' >> "$detailed_report"
      echo '\end{figure}' >> "$detailed_report"
      echo '' >> "$detailed_report"
    fi

    if "$is_CFDandMRT"; then

      # Vertical air temperature difference discomfort graph.
      if "$is_vertdT_discomfort"; then
        timebase="$(awk -f "$script_dir/get_timebase.awk" "$tmp_dir/vertdT_discomfort")"
        echo '\begin{figure}[h]' >> "$detailed_report"
        echo '\centering' >> "$detailed_report"
        echo '\begin{tikzpicture}' >> "$detailed_report"
        echo '\begin{axis}[' >> "$detailed_report"
        echo '/pgf/number format/1000 sep={ },' >> "$detailed_report"
        echo 'legend style= {at={(0.5,1.02)}, anchor=south },' >> "$detailed_report"
        echo 'legend columns = 5,' >> "$detailed_report"
        if [ $num_sim_days -gt 7 ]; then
          echo 'width=20cm,' >> "$detailed_report"
          echo 'height=10cm,' >> "$detailed_report"
          echo 'xlabel={Time (days)},' >> "$detailed_report"
          echo 'xmin={'"$xmin"'},' >> "$detailed_report"
          xmax="$num_sim_days"
          echo 'xmax={'"$xmax"'},' >> "$detailed_report"
        else
          echo 'width=20cm,' >> "$detailed_report"
          echo 'height=10cm,' >> "$detailed_report"
          echo 'xlabel={Time (hours)},' >> "$detailed_report"
          echo 'xmin={'"$xmin"'},' >> "$detailed_report"
          xmax=$((num_sim_days*24))
          echo 'xmax={'"$xmax"'},' >> "$detailed_report"
        fi
        echo 'ylabel={discomfort due to head-to-foot air temperature difference (\%)},' >> "$detailed_report"
        echo ']' >> "$detailed_report"

        # Loop over sensors with discomfort.
        i0_zone=-1
        i0_colour=-1
        legend=''
        for i0_sensor in "${array_sensor_indices[@]}"; do
          if [ "${array_severity_vertdT[i0_sensor]}" -gt 0 ]; then

            # Set colour by zone and mark by sensor.
            i0_zone_prev="$i0_zone"
            i0_zone="$((array_sensor_zones[i0_sensor]-1))"
            zone_name="${array_zone_names[i0_zone]}"
            sensor_name="${array_MRTsensor_names[i0_sensor]}"  
            if [ "$i0_zone" -gt "$i0_zone_prev" ]; then 
              ((i0_colour++))
              i0_mark=0
            else
              ((i0_mark++))
            fi

            # Add a plot for each occupied period.
            i=1
            while [ "$i" -le "${array_num_vertdT_plotFiles[i0_sensor]}" ]; do
              echo '\addplot['"color=${array_pgfColours[i0_colour]},mark=${array_pgfMarks[i0_mark]}"'] table [' >> "$detailed_report"
              if [ $num_sim_days -gt 7 ]; then
                echo 'x expr=(\thisrowno{0}-'"$timebase"'),' >> "$detailed_report"
              else
                echo 'x expr=(\thisrowno{0}-'"$timebase"')*24,' >> "$detailed_report"
              fi
              echo ']' >> "$detailed_report"
              echo '{'"$tmp_dir/sen$i0_sensor-vertdT-$i.txt"'};' >> "$detailed_report"
              if [ "$i" -eq 1 ]; then
                legend="${legend}${zone_name} ${sensor_name},"
                num_commas=-1
              else
                legend="${legend},"
                ((num_commas--))
              fi          
              ((i++))
            done
          fi
        done

        # Define discomfort criteria line.
        echo '\addplot[black, dashed, samples=2, domain='"$xmin:$xmax"'] {'"$vertdT_criteria"'};' >> "$detailed_report"

        echo '\legend{'"${legend:0:$num_commas}"'}' >> "$detailed_report"

        echo '\end{axis}' >> "$detailed_report"
        echo '\end{tikzpicture}' >> "$detailed_report"
        echo '\end{figure}' >> "$detailed_report"
        echo '' >> "$detailed_report"
      fi

      # Draught discomfort graph.
      if "$is_draught_discomfort"; then
        timebase="$(awk -f "$script_dir/get_timebase.awk" "$tmp_dir/draught_discomfort")"
        echo '\begin{figure}[h]' >> "$detailed_report"
        echo '\centering' >> "$detailed_report"
        echo '\begin{tikzpicture}' >> "$detailed_report"
        echo '\begin{axis}[' >> "$detailed_report"
        echo '/pgf/number format/1000 sep={ },' >> "$detailed_report"
        echo 'legend style= {at={(0.5,1.02)}, anchor=south },' >> "$detailed_report"
        echo 'legend columns = 5,' >> "$detailed_report"
        if [ $num_sim_days -gt 7 ]; then
          echo 'width=20cm,' >> "$detailed_report"
          echo 'height=10cm,' >> "$detailed_report"
          echo 'xlabel={Time (days)},' >> "$detailed_report"
          echo 'xmin={'"$xmin"'},' >> "$detailed_report"
          xmax="$num_sim_days"
          echo 'xmax={'"$xmax"'},' >> "$detailed_report"
        else
          echo 'width=20cm,' >> "$detailed_report"
          echo 'height=10cm,' >> "$detailed_report"
          echo 'xlabel={Time (hours)},' >> "$detailed_report"
          echo 'xmin={'"$xmin"'},' >> "$detailed_report"
          xmax=$((num_sim_days*24))
          echo 'xmax={'"$xmax"'},' >> "$detailed_report"
        fi
        echo 'ylabel={Draught rating (\%)},' >> "$detailed_report"
        echo ']' >> "$detailed_report"

        # Loop over sensors with discomfort.
        i0_zone=-1
        i0_colour=-1
        legend=''
        for i0_sensor in "${array_sensor_indices[@]}"; do
          if [ "${array_severity_opt[i0_sensor]}" -gt 0 ]; then

            # Set colour by zone and mark by sensor.
            i0_zone_prev="$i0_zone"
            i0_zone="$((array_sensor_zones[i0_sensor]-1))"
            zone_name="${array_zone_names[i0_zone]}"
            sensor_name="${array_MRTsensor_names[i0_sensor]}"  
            if [ "$i0_zone" -gt "$i0_zone_prev" ]; then 
              ((i0_colour++))
              i0_mark=0
            else
              ((i0_mark++))
            fi

            # Add a plot for each occupied period.
            i=1
            while [ "$i" -le "${array_num_draught_plotFiles[i0_sensor]}" ]; do
              echo '\addplot['"color=${array_pgfColours[i0_colour]},mark=${array_pgfMarks[i0_mark]}"'] table [' >> "$detailed_report"
              if [ $num_sim_days -gt 7 ]; then
                echo 'x expr=(\thisrowno{0}-'"$timebase"'),' >> "$detailed_report"
              else
                echo 'x expr=(\thisrowno{0}-'"$timebase"')*24,' >> "$detailed_report"
              fi
              echo ']' >> "$detailed_report"
              echo '{'"$tmp_dir/sen$i0_sensor-draught-$i.txt"'};' >> "$detailed_report"
              if [ "$i" -eq 1 ]; then
                legend="${legend}${zone_name} ${sensor_name},"
                num_commas=-1
              else
                legend="${legend},"
                ((num_commas--))
              fi          
              ((i++))
            done
          fi
        done

        # Define discomfort criteria line.
        echo '\addplot[black, dashed, samples=2, domain='"$xmin:$xmax"'] {'"$draught_criteria"'};' >> "$detailed_report"

        echo '\legend{'"${legend:0:$num_commas}"'}' >> "$detailed_report"

        echo '\end{axis}' >> "$detailed_report"
        echo '\end{tikzpicture}' >> "$detailed_report"
        echo '\end{figure}' >> "$detailed_report"
        echo '' >> "$detailed_report"
      fi
    fi

    # Daily mean temperature drift graph.
    if "$is_optDD_discomfort" || "$is_optWD_discomfort"; then
      timebase="$(awk -f "$script_dir/get_timebase.awk" $DMopt_awk_input)"
      echo '\begin{figure}[h]' >> "$detailed_report"
      echo '\centering' >> "$detailed_report"
      echo '\begin{tikzpicture}' >> "$detailed_report"
      echo '\begin{axis}[' >> "$detailed_report"
      echo '/pgf/number format/1000 sep={ },' >> "$detailed_report"
      echo 'legend style= {at={(0.5,1.02)}, anchor=south },' >> "$detailed_report"
      echo 'legend columns = 5,' >> "$detailed_report"
      echo 'width=20cm,' >> "$detailed_report"
      echo 'height=10cm,' >> "$detailed_report"
      echo 'xlabel={Time (days)},' >> "$detailed_report"
      #echo 'xmin={'"$xmin"'},' >> "$detailed_report"
      xmax="$num_sim_days"
      #echo 'xmax={'"$xmax"'},' >> "$detailed_report"
      echo 'ylabel={daily mean operative temperature (\si{\celsius})},' >> "$detailed_report"
      echo ']' >> "$detailed_report"

      # Loop over sensors with discomfort.
      i0_zone=-1
      i0_colour=-1
      legend=''
      for i0_sensor in "${array_sensor_indices[@]}"; do
        if [ "${array_severity_optDD[i0_sensor]}" -gt 0 ] || [ "${array_severity_optWD[i0_sensor]}" -gt 0 ]; then

          # Set colour by zone and mark by sensor.
          i0_zone_prev="$i0_zone"
          i0_zone="$((array_sensor_zones[i0_sensor]-1))"
          zone_name="${array_zone_names[i0_zone]}"
          sensor_name="${array_MRTsensor_names[i0_sensor]}"  
          if [ "$i0_zone" -gt "$i0_zone_prev" ]; then 
            ((i0_colour++))
            i0_mark=0
          else
            ((i0_mark++))
          fi

          # Add a plot for each occupied period.
          i=1
          while [ "$i" -le "${array_num_DMopt_plotFiles[i0_sensor]}" ]; do
            echo '\addplot['"color=${array_pgfColours[i0_colour]},mark=${array_pgfMarks[i0_mark]}"'] table [' >> "$detailed_report"
            echo 'x expr=(\thisrowno{0}-'"$timebase"'),' >> "$detailed_report"
            echo ']' >> "$detailed_report"
            echo '{'"$tmp_dir/sen$i0_sensor-DMopt-$i.txt"'};' >> "$detailed_report"
            if [ "$i" -eq 1 ]; then
              legend="${legend}${zone_name} ${sensor_name},"
              num_commas=-1
            else
              legend="${legend},"
              ((num_commas--))
            fi          
            ((i++))
          done

          # Add highlights.
          i=1
          while [ "$i" -le "${array_num_DMoptDailyHilite_plotFiles[i0_sensor]}" ]; do
            echo '\addplot['"color=${array_pgfColours[i0_colour]}"',dashed,no markers] table [' >> "$detailed_report"
            echo 'x expr=(\thisrowno{0}-'"$timebase"'),' >> "$detailed_report"
            echo ']' >> "$detailed_report"
            echo '{'"$tmp_dir/sen$i0_sensor-DMoptDailyHilite-$i.txt"'};' >> "$detailed_report"
            legend="${legend},"
            ((num_commas--))
            ((i++))
          done
          i=1
          while [ "$i" -le "${array_num_DMoptWeeklyHilite_plotFiles[i0_sensor]}" ]; do
            echo '\addplot['"color=${array_pgfColours[i0_colour]}"',dashed,no markers] table [' >> "$detailed_report"
            echo 'x expr=(\thisrowno{0}-'"$timebase"'),' >> "$detailed_report"
            echo ']' >> "$detailed_report"
            echo '{'"$tmp_dir/sen$i0_sensor-DMoptWeeklyHilite-$i.txt"'};' >> "$detailed_report"
            legend="${legend},"
            ((num_commas--))
            ((i++))
          done
        fi
      done

      echo '\legend{'"${legend:0:$num_commas}"'}' >> "$detailed_report"

      echo '\end{axis}' >> "$detailed_report"
      echo '\end{tikzpicture}' >> "$detailed_report"
      echo '\end{figure}' >> "$detailed_report"
      echo '' >> "$detailed_report"
    fi
  fi
else
  echo 'All locations, as analysed, have comfort metric values within the criteria and therefore are compliant with the standard.' >> "$report"

  if "$do_detailed_report"; then
    echo 'All locations, as analysed, have comfort metric values within the criteria and therefore are compliant with the standard.' >> "$detailed_report"
  fi
fi
echo '\end{addmargin}' >> "$report"
echo '' >> "$report"

if "$do_detailed_report"; then
  echo '\end{addmargin}' >> "$detailed_report"
  echo '' >> "$detailed_report"
fi

# Final processing on the report.
if $verbose; then echo " Generating pdf report ..."; fi
echo >> "$report"
echo '\end{landscape}' >> "$report"
echo '\end{document}' >> "$report"

# Compile three times to ensure longtable does its thing.
rm -f "${report:0:-4}.aux"
lualatex -halt-on-error -output-directory="$tmp_dir" "$report" > "$tmp_dir/lualatex.out"
lualatex -halt-on-error -output-directory="$tmp_dir" "$report" >> "$tmp_dir/lualatex.out"
lualatex -halt-on-error -output-directory="$tmp_dir" "$report" >> "$tmp_dir/lualatex.out"
mv "${report:0:-4}.pdf" "$report_final"

if "$do_detailed_report"; then
  if $verbose; then echo " Generating detailed pdf report ..."; fi
  echo >> "$detailed_report"
  echo '\end{landscape}' >> "$detailed_report"
  echo '\end{document}' >> "$detailed_report"

  rm -f "${detailed_report:0:-4}.aux"
  lualatex -halt-on-error -output-directory="$tmp_dir" "$detailed_report" >> "$tmp_dir/lualatex.out"
  lualatex -halt-on-error -output-directory="$tmp_dir" "$detailed_report" >> "$tmp_dir/lualatex.out"
  lualatex -halt-on-error -output-directory="$tmp_dir" "$detailed_report" >> "$tmp_dir/lualatex.out"
  mv "${detailed_report:0:-4}.pdf" "$detailed_report_final"
fi

# Check report exists.
if ! [ -f "$report_final" ]; then
  echo "Error: failed to write pdf output." >&2
  exit 110
fi

if "$verbose"; then 
  echo " Done"
  echo
  echo "***** CIBSE PAM END"
fi
