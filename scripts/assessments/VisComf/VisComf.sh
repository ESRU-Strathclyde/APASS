#! /bin/bash

# BS EN 12464-1 Performance Assessment Method - ESP-r implementation
# Version 2.1 of June 2017.

# Implementation-specific error codes:
# 201 - could not create temporary directory
# 202 - problem with simulation preset
# 203 - model name is empty
# 204 - other problem with model (error output from esp-query should specify)

# Set up defaults.
building=""
results_file="simulation_results"
start="1 1"
finish="31 12"
year="2000"
timesteps=1
startup=5
preset=""
tmp_dir="./tmp"
report_final="./report.pdf"
detailed_report_final="./detailed_report.pdf"
JSON="./data.json"
information=false
verbose=false
UGR_category="C"
preamble_file=""
do_simulation=true
do_radiance=true
do_detailed_report=false

# Get paths to call the various other scripts used by this program.
script_dir="$(dirname "$(readlink -f "$0")")"
common_dir="$script_dir/../../common"

# Get current directory.
current_dir="$PWD"

# Parse command line.
while getopts ":hvf:p:t:s:d:r:R:j:c:P:UuS" opt; do
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
    c) UGR_category="$OPTARG";;
    P) preamble_file="$OPTARG";;
    U) do_simulation=false;;
    u) do_radiance=false;;
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
  echo " Usage: ./12464-1.sh [OPTIONS] model-cfg-file"
  echo
  echo " ESP-r implementation of the 12464-1 Performance Assessment Method."
  echo
  echo " Command line options: -h"
  echo "                          display help text and exit"
  echo "                          default: off"
  echo "                       -v"
  echo "                          verbose output to stdout"
  echo "                          default: off"
  echo "                       -f results-file"
  echo "                          file name of the simulation results (output from BPS)"
  echo "                          default: ./simulation_results.res"
  echo "                       -p start-day_start-month_finish-day_finish-month_year"
  echo "                          start and end days of simulation period"
  echo "                          default: 1_1_31_12_2000"
  echo "                       -t timesteps"
  echo "                          number of timesteps per hour"
  echo "                          default: 1"
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
  echo "                       -c {A,B,C,D,E}"
  echo "                          Comfort criteria, representing 16, 19, 22, 25 and 28 UGR."
  echo "                          default: C"
  echo "                       -i model-image"
  echo "                          image in .pdf, .png, .jpg or .eps format."
  echo "                          default: PAM will automatically generate a wireframe image of the model"
  echo "                       -P preamble-file"
  echo "                          text in this file will be placed in the report before analysis outcomes"
  echo "                          default: none"
  echo "                       -U" 
  echo "                          Do not simulate and use existing results libraries"
  echo "                          default: off"
  echo "                       -u" 
  echo "                          Do not run radiance and use existing views and UGR values"
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

# TODO - more detailed criteria selection? Usage zone directives in ESP-r?
# BS EN 12464-1 has a terrifyingly exhaustive list of lighting requirements for specific spaces.
# However, all of these have UGR criteria of 16, 19, 22, 25 or 28.
# For the time being then, select criteria for the whole building according to a letter A - E (respectively).
if [ "$UGR_category" == "A" ]; then
  UGR_criteria="16"
elif [ "$UGR_category" == "B" ]; then
  UGR_criteria="19"
elif [ "$UGR_category" == "C" ]; then
  UGR_criteria="22"
elif [ "$UGR_category" == "D" ]; then
  UGR_criteria="25"
elif [ "$UGR_category" == "E" ]; then
  UGR_criteria="28"
else
  echo "Error: UGR category argument \"$UGR_category\" not recognised." >&2
  exit 107
fi

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



if $verbose; then echo "***** 12464-1 PAM START"; fi

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
"$common_dir/esp-query/esp-query.py" -o "$tmp_dir/query_results.txt" "$building" "model_name" "model_description" "number_zones" "zone_control" "MRT_sensors" "MRT_sensor_names" "afn_network" "zone_names" "uncertainties_file"

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

# Assemble array of zone names.
zone_names="$(awk -f "$common_dir/esp-query/processOutput_getSpaceSeparatedZoneNames.awk" "$tmp_dir/query_results.txt")"
array_zone_names=($zone_names)

# Check zone control.
zone_control="$(awk -f "$common_dir/esp-query/processOutput_getZoneControl.awk" "$tmp_dir/query_results.txt")"

# Check for afn network.
afn_network="$(awk -f "$common_dir/esp-query/processOutput_getAFNnetwork.awk" "$tmp_dir/query_results.txt")"
if [ "X$afn_network" == "X" ]; then
  is_afn=false
else
  is_afn=true
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

# Get results file location, simulation period, timesteps and startup days if a simulation preset is defined.
sim_results_preset=""
mf_results_preset=""
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

# Disable existing radiance directives and CFD domains.
sed -e 's/^\(\*rif *\)/# \1/' -i "$building"
sed -e 's/^\(\*cfd *\)/# \1/g' -i "$building"



# *** SIMULATE ***

# Set up paths.
if [ "X$up_one" == "X" ]; then
  building_tmp="$building"
  tmp_dir_tmp="$tmp_dir"
  sim_results_tmp="$sim_results"
  mf_results_tmp="$mf_results"
else
  cd ..
  building_tmp="$up_one/$building"
  tmp_dir_tmp="$up_one/$tmp_dir"
  sim_results_tmp="$up_one/$sim_results"
  mf_results_tmp="$up_one/$mf_results"
fi

if $do_simulation; then

  # Update progress file.
  echo '3' > "$tmp_dir_tmp/progress.txt"

  # Make sure there is no existing results library or ACC-actions file. 
  # Suppress output in case there isn't to prevent chatter.
  rm -f "$sim_results_tmp" > /dev/null
  if $is_afn; then rm -f "$mf_results_tmp" > /dev/null; fi

  # Update simulation year in cfg file.
  sed -i -e 's/\*year *[0-9]*/*year '"$year"'/' "$building_tmp"

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
    bps -mode script -file "$building_tmp" -p "$preset" silent > "$tmp_dir_tmp/bps.out"

    mv "$sim_results_preset" "$sim_results_tmp"
    if $is_afn; then
      mv "$mf_results_preset" "$mf_results_tmp"
    fi
  else
    bps_script="
c
${sim_results_tmp}"
    if $is_afn; then
      bps_script="$bps_script
${mf_results_tmp}"
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
    bps_script="$bps_script
s"
    if [ "$zone_control" -eq 1 ]; then
      bps_script="$bps_script
y"
    fi
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

fi



# *** EXTRACT RESULTS ***

# Update progress file.
echo '4' > "$tmp_dir/progress.txt"

# Run res to get occupied hours.
if ! [ "X$up_one" == "X" ]; then
  cd .. || exit 1
fi

res -mode script -file "$sim_results_tmp" > "$tmp_dir_tmp/res.out" <<~

c
g
>
b
${tmp_dir_tmp}/occupancy_timestep

+
b
*
a
j
e
-
!
>
+
-
-
d
c
>
b
${tmp_dir_tmp}/occupied_hours
j
e
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

if ! [ "X$up_one" == "X" ]; then
  cd "$up_one" || exit 1
fi

# Extract data from res output.
ocup="$(awk -f "$script_dir/get_occupiedHours.awk" "$tmp_dir/occupied_hours")"

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

# Check for MRT sensors.
MRT_sensors="$(awk -f "$common_dir/esp-query/processOutput_getSpaceSeparatedMRTsensors.awk" "$tmp_dir/query_results.txt")"
array_MRT_sensors=($MRT_sensors)
is_MRT=false
number_MRT_sensors=0
for n in $MRT_sensors; do
  if [ "$n" -gt 0 ]; then 
    if ! $is_MRT; then is_MRT=true; fi
    ((number_MRT_sensors+=n))
  fi
done

if ! $is_MRT; then
# No MRT sensors, exit with an error.
  echo "Error: no MRT sensors detected in this model." >&2
  exit 106
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

if $do_radiance; then

  # Automate view generation.
  # Use e2r to set up all the options files, but do the actual rendering
  # manually; this allows us closer control over file names and processing order.
  e2r_script="c
  autogen.rcf"
  i=0
  not_first=false
  skip=true
  for i1_zone in "${array_zones_with_MRTsensors[@]}"; do
    i0_zone=$((i1_zone-1))
    array_zoneWithMRT_has_results[i0_zone]=false
    if "$skip"; then
      skip=false
    fi
    if "$not_first"; then
      e2r_script="$e2r_script
c
*
a"
    fi
    scene="$(printf "z%02d" $i1_zone)"
    e2r_script="$e2r_script
b
c
<
1
${i1_zone}
$scene

a
2"

    # Loop over days in the simulation.
    jDay="$simS_JD"
    while [ "$jDay" -le "$simF_JD" ]; do

      # Get the days occupancy pattern.
      hour_ocup="$(awk -v jDay="$jDay" -v zone="$i1_zone" -f "$script_dir/get_singleDayOccupiedHours.awk" "$tmp_dir/occupancy_timestep")"
      array_hour_ocup=($hour_ocup)

      # Loop over hours in the day.
      i0_hour=0
      for i0_hour in 9 12 15 18; do
      #while [ "$i0_hour" -lt 24 ]; do
        if [ "${array_hour_ocup[i0_hour]}" -gt 0 ]; then
          if ! ${array_zoneWithMRT_has_results[i0_zone]}; then array_zoneWithMRT_has_results[i0_zone]=true; fi
          i1_hour="$((i0_hour+1))"
          sky_name="$(printf 'z%02d_d%03d_h%02d.sky' $i1_zone $jDay $i1_hour)"
          JD2DM "$jDay"
          e2r_script="$e2r_script
d
${sky_name}
d
${dayMonth} ${i0_hour}
g
-"
        fi
        #((i0_hour++))
      done
      ((jDay++))
    done

    e2r_script="$e2r_script
g
<
1
${i1_zone}
c
-
*
-
-
b"

    # Uncomment this to generate very quick, but low quailty views.
    e2r_script="$e2r_script
h
c
a
>

-"

    e2r_script="$e2r_script
>"

  #   zn_ind=$((i1_zone-1))
  #   vp_num=1
  #   while [ "$vp_num" -le "${array_MRT_sensors[zn_ind]}" ]; do
  # #    if [ "$vp_num" -lt 10 ]; then
  # #      vp="vew0$vp_num"
  # #    else
  # #      vp="vew$vp_num"
  # #    fi
  #     vp="$(printf "vew%02d" $vp_num)"
  #     hdr="$building_dir/../rad/scene_${i}_${vp}.hdr"
  #     glr="$building_dir/../rad/scene_${i}_${vp}.glr"
  # # In cases with blind control, views may have "_a" added to the name between i and vp.
  #     hdr_alt="$building_dir/../rad/scene_${i}_a_${vp}.hdr"
  #     glr_alt="$building_dir/../rad/scene_${i}_a_${vp}.glr"
  # # Remove any existing views.
  #     if [ -f "$hdr" ]; then
  #       rm -f "$hdr"
  #     fi
  #     if [ -f "$glr" ]; then
  #       rm -f "$glr"
  #     fi
  #     if [ -f "$hdr_alt" ]; then 
  #       rm -f "$hdr_alt"
  #     fi
  #     if [ -f "$glr_alt" ]; then
  #       rm -f "$glr_alt"
  #     fi
  #     e2r_script="$e2r_script
  # i
  # <
  # 1
  # ${vp_num}"
  #     ((vp_num++))
  #   done

    ((i++))
    not_first=true
  done
  e2r_script="$e2r_script
-"

  if "$skip"; then
    echo "Error: no occupancy detected in any zones with MRT sensors."
    exit 106
  fi

  echo "$e2r_script" > "$tmp_dir/e2r.script"

  cd "$building_dir" || exit 1

  e2r -mode script -file "$building_base" <<~ > "$current_dir/$tmp_dir/e2r.out" 2>&1
${e2r_script}
~

  cd ../rad || exit 1

  # We now have a bunch of rif files called "zAA.rif", 
  # and a bunch of sky files called "zAA_dCCC_hDD.sky".
  # We aim to end up with a load of fisheye renderings called "zAA_vBB_dCCC_hDD.hdr",
  # and for each viewpoint, UGR results at all hours called "zAA_vBB.ugr".

  radout="${current_dir}/${tmp_dir}/rad.out"
  rpictout="${current_dir}/${tmp_dir}/rpict.out"
  for rifFile in z??.rif; do

    vpNames="$(awk -f "$script_dir/get_rifViewpoints.awk" "$rifFile")"
    array_vpNames=($vpNames)
    zcode="${rifFile:0:3}"
    for vp in "${array_vpNames[@]}"; do
      vcode="$vp"
      for skyFile in ${zcode}_d???_h??.sky; do
        dhcode="${skyFile:4:8}"
        # Replace sky file reference in rif file.
        sed -e 's/scene= .*\.sky/scene= '"$skyFile"'/' -i "$rifFile"
        # Generate hdr.
        rad -v "$vp" "$rifFile" "oconv=-w" "rpict=-e $rpictout" > "$radout"
        mv "${zcode}_${vcode}.hdr" "${zcode}_${vcode}_${dhcode}.hdr"
        # Run findglare.
        rendopt="$(awk 'BEGIN{ORS=" "}; {print $0}' "${zcode}.opt")"
        findglare -p "${zcode}_${vcode}_${dhcode}.hdr" "$rendopt" "${zcode}.oct" > "${zcode}_${vcode}_${dhcode}.glr"
        # Assess UGR.
        ugrFile="${zcode}_${vcode}_${dhcode}.ugr"
        glarendx -t 'ugr' -h "${zcode}_${vcode}_${dhcode}.glr" > "${ugrFile}"
        if [ ! -f "$ugrFile" ]; then
          echo "Error: failed to retrieve UGR file $ugrFile"
          exit 205
        fi
        # Check for an empty file, assume this means assessment has failed and write an appropriate replacement.
        out="$(cat $ugrFile)"
        if [ "X$out" == "X" ]; then        
          echo '0.0 failed' > "$ugrFile"
        fi
        # Remove octree to ensure it is refreshed with the next sky file.
        rm "${rifFile:0:3}.oct"
      done

  # Now, combine UGR results for this viewpoint.
      awk -f "$script_dir/combine_UGRrowData.awk" ${zcode}_${vcode}_d???_h??.ugr > "${zcode}_${vcode}.ugr"
    done
  done

  cd "$current_dir" || exit 1

fi

# # Wait for radiance to finish plotting glare sources on the pictures and writing output files.
# out=XXX
# while [ ! "X$out" == "X" ]; do
#   out="$(ps | grep "xglaresrc")"
#   sleep 1
# done

# opened="$(wmctrl -l)"

# i=0
# j=0
# for a in "${array_zones_with_MRTsensors[@]}"; do
#   if [ "${array_maxs[i]}" == "x" ]; then
#     ((i++))
#     continue
#   fi
#   zn_ind=$((a-1))
#   vp_num=1
#   b="$(printf "%02d" $a)"
#   while [ "$vp_num" -le "${array_MRT_sensors[zn_ind]}" ]; do
# #    if [ "$vp_num" -lt 10 ]; then
# #      vp="vew0$vp_num"
# #    else
# #      vp="vew$vp_num"
# #    fi
#     vp="$(printf "vew%02d" $vp_num)"

#     vp_pad="$(printf "%03d" $vp_num)"

# # # Screenshot the pictures then close them.
# #     window_name="scene_${i}_${vp}.hdr"
# #     alt=false
# #     if [ "X$(echo "$opened" | grep "$window_name")" == "X" ]; then
# # # In cases with blind control, views may have "_a" added to the name between i and vp.
# #       window_name_alt="scene_${i}_a_${vp}.hdr"
# #       if [ "X$(echo "$opened" | grep "$window_name_alt")" == "X" ]; then      
# #         echo "Error: failed to retrieve UGR for view $window_name"
# #         exit 205
# #       else
# #         window_name="$window_name_alt"
# #         alt=true
# #       fi
# #     fi
# #     import -window "$window_name" "$tmp_dir/$b-vp-$vp_pad.pdf"
# #     sleep 0.5
# #     wmctrl -c "$window_name"
# # # If we try and close them too quick it fails, wait half a second between.
# #     sleep 0.5

# # Get UGR results.
#     if "$alt"; then
#       glr_name="scene_${i}_a_${vp}.glr"
#       ugr_name="$glr_name.ugr"
#     else      
#       glr_name="scene_${i}_${vp}.glr"
#       ugr_name="$glr_name.ugr"
#     fi
#     glarendx -t ugr -h "$building_dir/../rad/$glr_name" > "$building_dir/../rad/$ugr_name"
#     if [ ! -f "$building_dir/../rad/$ugr_name" ]; then
#       echo "Error: failed to retrieve UGR for view $window_name"
#       exit 205
#     fi
#     cp "$building_dir/../rad/$ugr_name" "$tmp_dir/$b-vp-$vp_pad.ugr"

# # Assemble arrays:
# # Viewpoint identifiers.
#     array_vp_names[j]="$b-vp-$vp_pad"
# # Viewpoint zones.
#     array_vp_zones[j]="$a"

#     ((j++))

#     ((vp_num++))
#   done
#   ((i++))
# done

# Update progress file.
echo '7' > "$tmp_dir/progress.txt"

# Generate array of zone and viewpoint codes for each sensor.
i0_sensor=0
for i1_zone in "${array_zones_with_MRTsensors[@]}"; do
  i0_zone="$((i1_zone-1))"
  n="${array_MRT_sensors[i0_zone]}" 
  i1=1
  while [ "$i1" -le "$n" ]; do
    array_sensor_zvcodes[i0_sensor]="$(printf 'z%02d_v%02d' $i1_zone $i1)"
    ((i1++))
    ((i0_sensor++))
  done
done

# Retreive UGR results from rad folder and combine.
UGR="$(awk -f "$script_dir/combine_UGRcolumnData.awk" $building_dir/../rad/z??_v??.ugr)"
echo "$UGR" > "$tmp_dir/UGR.txt"

# Get deviation from comfort criteria.
deviation="$(awk -v criteria="$UGR_criteria" -f "$script_dir/get_deviation.awk" "$tmp_dir/UGR.txt")"
echo "$deviation" > "$tmp_dir/deviation.trace"

# Get time of worst discomfort.
TWD="$(awk -f "$script_dir/get_timeWorstDiscomfort.awk" "$tmp_dir/UGR.txt")"
array_TWD=($TWD)
echo "$TWD" > "$tmp_dir/TWD.trace"

# Get percentage time in discomfort.
PTD="$(echo "$deviation" | awk -f "$script_dir/get_percentTimeDiscomfort.awk")"
array_PTD=($PTD)
echo "$PTD" > "$tmp_dir/PTD.trace"

# Calculate severity ratings.
severity="$(echo "$PTD" | awk -v criteria="$UGR_criteria" -f "$script_dir/get_severityRating.awk")"
array_severity=($severity)
echo "$severity" > "$tmp_dir/severity.trace"

# Check for any discomfort.
performance_flag=0
for s in "${array_severity[@]}"; do
  if [ "$s" == '1' ]; then 
    performance_flag=1
    break
  fi
done

echo "$performance_flag" > "$tmp_dir/pflag.txt"

if "$do_detailed_report"; then

  # For each location with discomfort, dump data for each metric during occupied hours into separate file for graphing.
  i0_result=0
  for i0_sensor in "${array_sensor_indices[@]}"; do
    i0_zone="$((array_sensor_zones[i0_sensor]-1))"
    if ${array_zoneWithMRT_has_results[i0_zone]}; then
      i1_zone="$((i0_zone+1))"
      zone_name="${array_zone_names[i0_zone]}"
      sensor_name="${array_MRTsensor_names[i0_sensor]}"
      if [ "${array_severity[i0_result]}" -gt 0 ]; then
        i1_result="$((i0_result+1))"
        i=1
        output="$(awk -v zone="$i1_result" -v recursion="$i" -f "$script_dir/get_singleZoneAllRecursive.awk" "$tmp_dir/UGR.txt")"
        while [ ! "X$output" == "X" ]; do
          echo "$output" > "$tmp_dir/res$i1_result-$i"
          ((i++))    
          output="$(awk -v zone="$i1_result" -v recursion="$i" -f "$script_dir/get_singleZoneAllRecursive.awk" "$tmp_dir/UGR.txt")"
        done
        array_num_plotFiles[i0_result]="$((i-1))"

        # Also, grab a screenshot of glare sources at the worst time.
        zvcode="${array_sensor_zvcodes[i0_sensor]}"
        TWD="${array_TWD[i0_result]}"
        TWD_time="${TWD#*_}"
        TWD_hour="$(echo "${TWD_time:0:2}" | awk '{sub(/^0*/,"")}1')"
        code="$(printf '%s_d%03d_h%02d' "$zvcode" "${TWD%_*}" "$((TWD_hour+1))")"
        xglaresrc "$building_dir/../rad/${code}.hdr" "$building_dir/../rad/${code}.glr"
        import -window "${code}.hdr" "$tmp_dir/sen${i0_sensor}-WD.pdf"
        sleep 0.5
        wmctrl -c "${code}.hdr"
        sleep 0.5
      else
        array_num_plotFiles[i0_result]=0
      fi
      ((i0_result++))
    fi
  done
fi

# Update progress file.
echo '8' > "$tmp_dir/progress.txt"



# *** Write JSON file ***

echo '{' > "$JSON"

# If there is any discomfort, write directives.
if [ "$performance_flag" -gt 0 ]; then
  echo "  \"visual discomfort\": [" >> "$JSON"
  first=true
  i0_result=0
  for i0_sensor in "${array_sensor_indices[@]}"; do
    i0_zone="$((array_sensor_zones[i0_sensor]-1))"
    if ${array_zoneWithMRT_has_results[i0_zone]}; then
      i1_zone="$((i0_zone+1))"
      zone_name="${array_zone_names[i0_zone]}"
      sensor_name="${array_MRTsensor_names[i0_sensor]}"
      if [ "${array_severity[i0_result]}" -gt 0 ]; then          
        if $first; then
          first=false
        else
          echo "," >> "$JSON"
        fi
        echo '    {' >> "$JSON"
        echo "      \"area\": \"$zone_name\"," >> "$JSON"
        echo "      \"location\": \"$sensor_name\"," >> "$JSON"
        echo "      \"glare\": {" >> "$JSON"
        echo "        \"frequency of occurrence (%)\": \"${array_PTD[i0_result]}\"," >> "$JSON"
        JD="${array_TWD[i0_result]%_*}"
        JD2DM "$JD"
        s="${dayMonth#* }-${dayMonth% *} ${array_TWD[i0_result]#*_}"
        echo "        \"worst time\": \"$s\"" >> "$JSON"
        echo "      }" >> "$JSON"
        printf '    }' >> "$JSON"
      fi
      ((i0_result++))
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
echo '\setlength{\parindent}{0cm}' >> "$report"
echo '\pagestyle{empty}' >>"$report"
echo >> "$report"
echo '\begin{document}' >> "$report"
#echo '\begin{landscape}' >> "$report"

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
  echo '\usepackage{pgfplots}' >> "$detailed_report"
  echo '\usepackage{siunitx}' >> "$detailed_report"
  echo '\usetikzlibrary{plotmarks}' >> "$detailed_report"
#  echo '\usepgfplotslibrary{external}' >> "$detailed_report"
#  echo '\tikzexternalize' >> "$detailed_report"
  echo '\setlength{\parindent}{0cm}' >> "$detailed_report"
  echo '\pagestyle{empty}' >>"$detailed_report"
  echo >> "$detailed_report"
  echo '\begin{document}' >> "$detailed_report"
#  echo '\begin{landscape}' >> "$detailed_report"
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
  echo 'Rank-ordered assessment results for locations that do not comply with the standard.' >> "$report"
  echo ' \\' >> "$report"
  echo '' >> "$report"
  echo '\setlength\LTleft{0.5cm}' >> "$report"
  echo '\setlength\LTright\fill' >> "$report"
  echo '\setlength\LTpre{0cm}' >> "$report"
  echo '\setlength\LTpost{0cm}' >> "$report"

  if "$do_detailed_report"; then
    echo 'The table lists rank-ordered (by operative temperature) assessment results for locations that do not comply with the standard.' >> "$detailed_report"
    echo 'Next, comfort parameter values at locations that do not comply with the standard are shown, with criteria from the standard as dashed lines.' >> "$detailed_report"
    echo 'Finally, potential glare sources at the time of worst criteria violation are shown for locations that do not comply with the standard (unit are candelas/m\textsuperscript{2}).' >> "$detailed_report"
    echo ' \\' >> "$detailed_report"
    echo '' >> "$detailed_report"
    echo '\setlength\LTleft{0.5cm}' >> "$detailed_report"
    echo '\setlength\LTright\fill' >> "$detailed_report"
    echo '\setlength\LTpre{0cm}' >> "$detailed_report"
    echo '\setlength\LTpost{0cm}' >> "$detailed_report"
  fi

  # Table for all comfort metrics.
  echo '\begin{longtable}{l l p{3cm} p{4cm}}' >> "$report"
  echo '' >> "$report"
  echo '\hline' >> "$report"
  echo '\multirow{3}{*}{Area} & \multirow{3}{*}{Location} & \multirow{3}{3cm}{\centering{Frequency of UGR\\violating criteria\\(\%)}} & \multirow{3}{4cm}{\centering{Time of worst\\criteria violation\\(MM-DD HH:MM)}} \\' >> "$report"
  echo ' \\' >> "$report"
  echo ' \\' >> "$report"
  echo '\hline' >> "$report"
  echo '\endfirsthead' >> "$report"
  echo '' >> "$report"
  echo '\hline' >> "$report"
  echo '\multicolumn{4}{l}{\small\sl continued from previous page} \\' >> "$report"  
  echo '\hline' >> "$report"
  echo '\multirow{3}{*}{Area} & \multirow{3}{*}{Location} & \multirow{3}{3cm}{\centering{Frequency of UGR\\violating criteria\\(\%)}} & \multirow{3}{4cm}{\centering{Time of worst\\criteria violation\\(MM-DD HH:MM)}} \\' >> "$report"
  echo ' \\' >> "$report"
  echo ' \\' >> "$report"
  echo '\hline' >> "$report"
  echo '\endhead' >> "$report"
  echo '' >> "$report"
  echo '\hline' >> "$report"
  echo '\multicolumn{4}{r}{\small\sl continued on next page} \\' >> "$report"
  echo '\hline' >> "$report"
  echo '\endfoot' >> "$report"
  echo '' >> "$report"
  echo '\endlastfoot' >> "$report"
  echo '' >> "$report"

  if "$do_detailed_report"; then
    echo '\begin{longtable}{l l p{3cm} p{4cm}}' >> "$detailed_report"
    echo '' >> "$detailed_report"
    echo '\hline' >> "$detailed_report"
    echo '\multirow{3}{*}{Area} & \multirow{3}{*}{Location} & \multirow{3}{3cm}{\centering{Frequency of UGR\\violating criteria\\(\%)}} & \multirow{3}{4cm}{\centering{Time of worst\\criteria violation\\(MM-DD HH:MM)}} \\' >> "$detailed_report"
    echo ' \\' >> "$detailed_report"
    echo ' \\' >> "$detailed_report"
    echo '\hline' >> "$detailed_report"
    echo '\endfirsthead' >> "$detailed_report"
    echo '' >> "$detailed_report"
    echo '\hline' >> "$detailed_report"
    echo '\multicolumn{4}{l}{\small\sl continued from previous page} \\' >> "$detailed_report"  
    echo '\hline' >> "$detailed_report"
    echo '\multirow{3}{*}{Area} & \multirow{3}{*}{Location} & \multirow{3}{3cm}{\centering{Frequency of UGR\\violating criteria\\(\%)}} & \multirow{3}{4cm}{\centering{Time of worst\\criteria violation\\(MM-DD HH:MM)}} \\' >> "$detailed_report"
    echo ' \\' >> "$detailed_report"
    echo ' \\' >> "$detailed_report"
    echo '\hline' >> "$detailed_report"
    echo '\endhead' >> "$detailed_report"
    echo '' >> "$detailed_report"
    echo '\hline' >> "$detailed_report"
    echo '\multicolumn{4}{r}{\small\sl continued on next page} \\' >> "$detailed_report"
    echo '\hline' >> "$detailed_report"
    echo '\endfoot' >> "$detailed_report"
    echo '' >> "$detailed_report"
    echo '\endlastfoot' >> "$detailed_report"
    echo '' >> "$detailed_report"
  fi

  rm "$tmp_dir/PTD_table" > /dev/null

  # Rank order table entries.
  i0_result=0
  for i0_sensor in "${array_sensor_indices[@]}"; do
    i0_zone="$((array_sensor_zones[i0_sensor]-1))"
    if ${array_zoneWithMRT_has_results[i0_zone]}; then
      i1_zone="$((i0_zone+1))"
      zone_name="${array_zone_names[i0_zone]}"
      sensor_name="${array_MRTsensor_names[i0_sensor]}"
      if [ "${array_severity[i0_result]}" -gt 0 ]; then
        JD="${array_TWD[i0_result]%_*}"
        JD2DM "$JD"
        s="${dayMonth#* }-${dayMonth% *} ${array_TWD[i0_result]#*_}"
        echo "$zone_name & $sensor_name & \\hfil ${array_PTD[i0_result]} & \\hfil ${s} "'\\' >> "$tmp_dir/PTD_table"
      fi
      ((i0_result++))
    fi
  done

  sorted="$(awk -f "$script_dir/sort_PTDtableEntries" "$tmp_dir/PTD_table")"
  echo "$sorted" > "$tmp_dir/sorted.trace"

  echo "$sorted" >> "$report"
  echo '\end{longtable}' >> "$report"

  if "$do_detailed_report"; then
    echo "$sorted" >> "$detailed_report"
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

    # UGR graph
    timebase="$(awk -f "$script_dir/get_timebase.awk" "$tmp_dir/UGR.txt")"
    echo '\begin{figure}[h]' >> "$detailed_report"
    echo '\centering' >> "$detailed_report"
    echo '\begin{tikzpicture}' >> "$detailed_report"
    echo '\begin{axis}[' >> "$detailed_report"
    echo '/pgf/number format/1000 sep={ },' >> "$detailed_report"
    echo 'legend style= {at={(0.5,1.02)}, anchor=south },' >> "$detailed_report"
    echo 'legend columns = 4,' >> "$detailed_report"
    if [ $num_sim_days -gt 7 ]; then
      echo 'width=15cm,' >> "$detailed_report"
      echo 'height=10cm,' >> "$detailed_report"
      echo 'xlabel={Time (days)},' >> "$detailed_report"
      echo 'xmin={'"$xmin"'},' >> "$detailed_report"
      xmax="$num_sim_days"
      echo 'xmax={'"$xmax"'},' >> "$detailed_report"
    else
      echo 'width=15cm,' >> "$detailed_report"
      echo 'height=10cm,' >> "$detailed_report"
      echo 'xlabel={Time (hours)},' >> "$detailed_report"
      echo 'xmin={'"$xmin"'},' >> "$detailed_report"
      xmax=$((num_sim_days*24))
      echo 'xmax={'"$xmax"'},' >> "$detailed_report"
    fi
    echo 'ylabel={Unified Glare Rating},' >> "$detailed_report"
    echo ']' >> "$detailed_report"

    # Loop over sensors with discomfort.
    i0_result=0
    i0_zone_prev=-1
    i0_colour=-1
    legend=''
    for i0_sensor in "${array_sensor_indices[@]}"; do
      i0_zone="$((${array_sensor_zones[i0_sensor]}-1))"
      if ${array_zoneWithMRT_has_results[i0_zone]}; then
        if [ "${array_severity[i0_result]}" -gt 0 ]; then

          # Set colour by zone and mark by sensor.
          zone_name="${array_zone_names[i0_zone]}"
          sensor_name="${array_MRTsensor_names[i0_sensor]}"  
          if [ "$i0_zone" -gt "$i0_zone_prev" ]; then 
            ((i0_colour++))
            i0_mark=0
          else
            ((i0_mark++))
          fi
          i0_zone_prev="$i0_zone"

          # Add a plot for each occupied period.
          i1_result="$((i0_result+1))"
          i=1
          while [ "$i" -le "${array_num_plotFiles[i0_result]}" ]; do
            echo '\addplot['"color=${array_pgfColours[i0_colour]},mark=${array_pgfMarks[i0_mark]}"'] table [' >> "$detailed_report"
            if [ $num_sim_days -gt 7 ]; then
              echo 'x expr=(\thisrowno{0}-'"$timebase"'),' >> "$detailed_report"
            else
              echo 'x expr=(\thisrowno{0}-'"$timebase"')*24,' >> "$detailed_report"
            fi
            echo ']' >> "$detailed_report"
            echo '{'"$tmp_dir/res$i1_result-$i"'};' >> "$detailed_report"
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
        ((i0_result++))
      fi
    done

    # Define discomfort criteria line.
    echo '\addplot[black, dashed, samples=2, domain='"$xmin:$xmax"'] {'"$UGR_criteria"'};' >> "$detailed_report"

    echo '\legend{'"${legend:0:$num_commas}"'}' >> "$detailed_report"

    echo '\end{axis}' >> "$detailed_report"
    echo '\end{tikzpicture}' >> "$detailed_report"
    echo '\end{figure}' >> "$detailed_report"
    echo '' >> "$detailed_report"

    # Display glare sources at worst discomfort.
    i0_result=0
    for i0_sensor in "${array_sensor_indices[@]}"; do
      i0_zone="$((${array_sensor_zones[i0_sensor]}-1))"
      if ${array_zoneWithMRT_has_results[i0_zone]}; then
        if [ "${array_severity[i0_result]}" -gt 0 ]; then
          zone_name="${array_zone_names[i0_zone]}"
          sensor_name="${array_MRTsensor_names[i0_sensor]}"  
          echo '\begin{figure}[h]' >> "$detailed_report"
          echo '\centering' >> "$detailed_report"
          echo '\includegraphics[width=8cm]{'"$tmp_dir/sen${i0_sensor}-WD.pdf"'}' >> "$detailed_report"
          echo '\caption{'"location ${sensor_name} in area ${zone_name}"'.}' >> "$detailed_report"
          echo '\end{figure}' >> "$detailed_report"
        fi
        ((i0_result++))
      fi
    done
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
#echo '\end{landscape}' >> "$report"
echo '\end{document}' >> "$report"

# Compile three times to ensure longtable does its thing.
rm -f "${report:0:-4}.aux"
lualatex -halt-on-error -output-directory="$tmp_dir" -pdf "$report" > "$tmp_dir/lualatex.out"
lualatex -halt-on-error -output-directory="$tmp_dir" -pdf "$report" >> "$tmp_dir/lualatex.out"
lualatex -halt-on-error -output-directory="$tmp_dir" -pdf "$report" >> "$tmp_dir/lualatex.out"
mv "${report:0:-4}.pdf" "$report_final"

if "$do_detailed_report"; then
  if $verbose; then echo " Generating detailed pdf report ..."; fi
  echo >> "$detailed_report"
#  echo '\end{landscape}' >> "$detailed_report"
  echo '\end{document}' >> "$detailed_report"

  rm -f "${detailed_report:0:-4}.aux"
  lualatex -halt-on-error -output-directory="$tmp_dir" -pdf "$detailed_report" >> "$tmp_dir/lualatex.out"
  lualatex -halt-on-error -output-directory="$tmp_dir" -pdf "$detailed_report" >> "$tmp_dir/lualatex.out"
  lualatex -halt-on-error -output-directory="$tmp_dir" -pdf "$detailed_report" >> "$tmp_dir/lualatex.out"
  mv "${detailed_report:0:-4}.pdf" "$detailed_report_final"
fi

# Check report exists.
if ! [ -f "$report_final" ]; then
  echo "Error: failed to write pdf output." >&2
  exit 110
fi
