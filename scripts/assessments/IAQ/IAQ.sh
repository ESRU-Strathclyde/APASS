#! /bin/bash

# BS EN 15251 (indoor air quailty) Performance Assessment Method - ESP-r implementation
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
timesteps=1
startup=5
preset=""
tmp_dir="./tmp"
report_final="./report.pdf"
detailed_report_final="./detailed_report.pdf"
JSON="./data.json"
information=false
verbose=false
comfort_category="B"
preamble_file=""
do_simulation=true
do_detailed_report=false

# Get paths to call the various other scripts used by this program.
script_dir="$(dirname "$(readlink -f "$0")")"
common_dir="$script_dir/../../common"

# Get current directory.
current_dir="$PWD"

# Parse command line.
while getopts ":hvf:p:t:s:d:r:R:j:c:P:U" opt; do
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
    c) comfort_category="$OPTARG";;
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
  echo " Usage: ./15251IAQ.sh [OPTIONS] model-cfg-file"
  echo
  echo " ESP-r implementation of the 15251 (indoor air quality) Performance Assessment Method."
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
  echo "                       -j JSON-file"
  echo "                          file name of the json report"
  echo "                          default: ./data.json"
  echo "                       -c {A,B,C}"
  echo "                          Comfort criteria, representing 350, 500 and 800 ppm CO2 concentration above ambient."
  echo "                          default: B"
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

# Assume ambient CO2 concentration of 400 ppm.
if [ "$comfort_category" == "A" ]; then
  ppm_criteria="750"
elif [ "$comfort_category" == "B" ]; then
  ppm_criteria="900"
elif [ "$comfort_category" == "C" ]; then
  ppm_criteria="1200"
else
  echo "Error: comfort category argument \"$comfort_category\" not recognised." >&2
  exit 107
fi

# Convert ppm by volume from standard, to ppm by mass.
# 1.5286 = ratio of desity of CO2 to air at 20 deg. C and 1 atm.
ppm_mass_criteria="$(echo "$ppm_criteria" | awk '{printf "%.1f", $1*1.5286}')"

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



if $verbose; then echo "***** 15251 (IAQ) PAM START"; fi

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
"$common_dir/esp-query/esp-query.py" -o "$tmp_dir/query_results.txt" "$building" "model_name" "model_description" "number_zones" "CFD_domains" "zone_control" "MRT_sensors" "MRT_sensor_names" "afn_network" "zone_names" "ctm_network" "number_ctm" "afn_zon_nod_nums" "uncertainties_file"

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

# Check for air flow and contaminant networks.
afn_network="$(awk -f "$common_dir/esp-query/processOutput_getAFNnetwork.awk" "$tmp_dir/query_results.txt")"
if [ "X$afn_network" == "X" ]; then
  echo "Error: no air flow network defined for this model." >&2
  exit 999
fi
is_afn=true
ctm_network="$(awk -f "$common_dir/esp-query/processOutput_getCTMnetwork.awk" "$tmp_dir/query_results.txt")"
if [ "X$ctm_network" == "X" ]; then
  echo "Error: no contaminant network defined for this model." >&2
  exit 999
fi

# Check number of contaminants.
number_ctm="$(awk -f "$common_dir/esp-query/processOutput_getNumCTM.awk" "$tmp_dir/query_results.txt")"
if [ "$number_ctm" -ne "1" ]; then
  echo "Error: need 1 contaminant defined in network." >&2
  exit 999
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
      ((i_ind++))
      ((i++))
    done
  fi
done
if ! $is_MRT; then
  echo "Error: no occupant locations detected in this model." >&2
  exit 103
fi

# Check for CFD domains.
CFD_domains="$(awk -f "$common_dir/esp-query/processOutput_getSpaceSeparatedCFDdomains.awk" "$tmp_dir/query_results.txt")"
array_CFD_domains=($CFD_domains)
is_CFD=false
CFDdomain_count=0
j=0
for i in "${array_zone_indices[@]}"; do
  n="${array_CFD_domains[i]}"
  if [ "$n" -gt 1 ]; then
    is_CFD=true
    ((CFDdomain_count++))
#    CFD_start_hour='1.0'
#    CFD_finish_hour='24.99'
    CFD_start_hour='6.0'
    CFD_finish_hour='20.99'
    m="${array_MRT_sensors[i]}"
    if [ "$m" -gt 0 ]; then
      ((j++))
    fi
  fi
done

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
  rm -f "$mf_results_tmp" > /dev/null
  if $is_CFD; then rm -f "$cfd_results_tmp" > /dev/null; fi
  rm -f "$building_dir_tmp"/ACC-actions_*.rec > /dev/null
  rm -f "$building_dir_tmp"/cfd3dascii_* > /dev/null

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
    if $is_CFD; then
      mv "$cfd_results_preset" "$cfd_results_tmp"
    fi
  else
    bps_script="
c
${sim_results_tmp}
${mf_results_tmp}"
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

  if ! [ -f "$mf_results" ]; then
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

# Get array of AFN zone node indices.
AFNnod_indices="$(awk -f "$common_dir/esp-query/processOutput_getSpaceSeparatedAFNnodNums.awk" "$tmp_dir/query_results.txt")"
array_AFNnod_indices=($AFNnod_indices)

# Get CFD contaminant list.
if $is_CFD; then
  CFD_contam="$("$common_dir/esp-query/esp-query.py" "$building" "CFD_contaminants")"
fi

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

# Get CO2 concentration for occupied zones.
# TODO - ESP-r looks for the mfr library relative to the cfg directory unless you give it an aboslute path - change this?
res_script="
c
i
${current_dir}/${mf_results_tmp}
*
a"

# First, get results from the contaminant network.
for i1 in "${array_zones_with_MRTsensors[@]}"; do
  i0="$((i1-1))"
  i1_pad="$(printf "%03d" $i1)"
  res_script="$res_script
>
b
${tmp_dir_tmp}/CO2_${i1_pad}.txt

+
b
<
1
${i1}
m
<
1
${array_AFNnod_indices[i0]}
a
-
q
a
-
>
+"
done

# Get summaries.
res_script="$res_script
-
-
d
a
n"
for i1 in "${array_zones_with_MRTsensors[@]}"; do
  i0="$((i1-1))"
  i1_pad="$(printf "%03d" $i1)"
  res_script="$res_script
>
b
${tmp_dir_tmp}/CO2summary_${i1_pad}.txt

+
b
<
1
${i1}
m
<
1
${array_AFNnod_indices[i0]}
a
-
q
a
-
>
+"
done

res_script="$res_script
-
-
-"

# Now, get CFD results if available.
if $is_CFD; then

# CO2 concentration.
  res_script="$res_script
c
g
*
a"

  first=true
  for i1 in "${array_zones_with_MRTsensors[@]}"; do
    i0="$((i1-1))"

# Check if CO2 is tracked in each CFD domain.
    if [[ "$CFD_contam" == *zone#"$i1"=CO2* ]] || [[ "$CFD_contam" == *zone#"$i1"=CO_2* ]]; then
      array_is_CFDcontam[i0]=true
      i1_pad="$(printf "%03d" $i1)"
      res_script="$res_script
o"

# Open CFD library.
      if $first; then
        res_script="$res_script
${cfd_results_tmp}"
        first=false
      fi

# If there is more than 1 domain, need to find which one corresponds to this zone.
      if [ "$CFDdomain_count" -gt 1 ]; then
        ii0=0
        ii1=1
        id=1
        while [ "$ii1" -lt "$i1" ]; do
          if [ "${array_CFD_domains[ii0]}" -gt 1 ]; then
            ((id++))
          fi
          ((ii0++))
          ((ii1++))
        done
        res_script="$res_script
${id}"
      fi
      res_script="$res_script
+
b
>
b
${tmp_dir_tmp}/CFD_CO2_${i1_pad}.txt
"
      is1=1
      while [ "$is1" -le "${array_MRT_sensors[i0]}" ]; do
        res_script="$res_script
k
b
<
1
${is1}
a
-"
        ((is1++))
      done
      res_script="$res_script
!
>
+
-"
    else
      array_is_CFDcontam[i0]=false
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
    i0="$((i1-1))"

# Check if CO2 is tracked in each CFD domain.
    if ${array_is_CFDcontam[i0]}; then
      i1_pad="$(printf "%03d" $i1)"
      res_script="$res_script
o"

# If there is more than 1 domain, need to find which one corresponds to this zone.
      if [ "$CFDdomain_count" -gt 1 ]; then
        ii0=0
        ii1=1
        id=1
        while [ "$ii1" -lt "$i1" ]; do
          if [ "${array_CFD_domains[ii0]}" -gt 1 ]; then
            ((id++))
          fi
          ((ii0++))
          ((ii1++))
        done
        res_script="$res_script
${id}"
      fi
      res_script="$res_script
+
b"
      is1=1
      while [ "$is1" -le "${array_MRT_sensors[i0]}" ]; do
        res_script="$res_script
>
b
${tmp_dir_tmp}/CFD_CO2summary_${i1_pad}.txt
k
b
<
1
${is1}
a
-
>"
        ((is1++))
      done
      res_script="$res_script
+
-"
    fi
  done
  res_script="$res_script
-
-"
fi

res_script="$res_script
-
"

echo "$res_script" > "$tmp_dir_tmp/res_script.trace"

# Run res.
res -mode script -file "$sim_results_tmp" >> "$tmp_dir_tmp/res.out" <<~
${res_script}
~

if ! [ "X$up_one" == "X" ]; then
  cd "$up_one" || exit 1
fi

# Now, scan through CFD results and see if they make sense.
# If so, replace flow network results with CFD results.
# If not, use flow network results.
# Assume sensible range is 0 - 50 g/kg
if "$is_CFD"; then
  for i1 in "${array_zones_with_MRTsensors[@]}"; do
    i0="$((i1-1))"
    if "${array_is_CFDcontam[i0]}"; then
      i1_pad="$(printf "%03d" $i1)"
      a="${tmp_dir}/CFD_CO2_${i1_pad}.txt"
      is_nonsense="$(awk -v vmin=0 -v vmax=50 -f "$script_dir/check_results.awk" "$a")"
      if [ "$is_nonsense" -eq 0 ]; then
        mv "$a" "${a/'/CFD_'/'/'}"
        b="${a/_CO2_/_CO2summary_}"
        mv "$b" "${b/'/CFD_'/'/'}"
        array_use_CFDresults[i0]=true
      elif [ "$is_nonsense" -eq 1 ]; then
        array_use_CFDresults[i0]=false
      fi
    else
      array_use_CFDresults[i0]=false
    fi
  done
fi

# Combine CO2 results if needed.
if [ "${#array_zones_with_MRTsensors[@]}" -gt 1 ]; then
  x="$(awk -f "$script_dir/combine_columnData.awk" $tmp_dir_tmp/CO2_*.txt)"
  echo "$x" > "$tmp_dir_tmp/CO2.txt"
else
  mv $tmp_dir_tmp/CO2_*.txt "$tmp_dir_tmp/CO2.txt"
fi

# Combine CO2 summaries.
if [ "${#array_zones_with_MRTsensors[@]}" -gt 1 ]; then
  x="$(awk -f "$script_dir/combine_CO2summaries.awk" $tmp_dir_tmp/CO2summary_*.txt)"
  echo "$x" > "$tmp_dir_tmp/CO2summary.txt"
else
  mv $tmp_dir_tmp/CO2summary_*.txt "$tmp_dir_tmp/CO2summary.txt"
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

DM2JD "$start"
simS_JD="$julianDay"
DM2JD "$finish"
simF_JD="$julianDay"

# Extract data from res output.
ocup="$(awk -f "$script_dir/get_occupiedHoursLatex.awk" "$tmp_dir/occupied_hours")"

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
    if [ ${a/.} -gt 0 ]; then
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

# Calculate deviation of CO2 concentration from comfort criteria.
# Results from ESP-r are in g/kg, so we need to divide the PPM by mass criteria by 1000.
esp_criteria="$(echo "$ppm_mass_criteria" | awk '{print $1/1000}')"
deviation="$(awk -v criteria="$esp_criteria" -f "$script_dir/get_deviation" "$tmp_dir/CO2.txt")"
echo "$deviation" > "$tmp_dir/deviation.trace"

# Find percentage of occupied time in discomfort (PTD).
PTD="$(echo "$deviation" | awk -f "$script_dir/get_percentTimeDiscomfort.awk")"
array_PTD=($PTD)

echo "${array_PTD[@]}" > "$tmp_dir/PTD.trace"

# Calculate severity ratings.
severity="$(echo "$PTD" | awk -f "$script_dir/get_severityRating.awk")"
array_severity=($severity)

echo "${array_severity[@]}" > "$tmp_dir/severity.trace"

# Set performance flag if any discomfort is found.
performance_flag=0
i=0
first=true
for sev in "${array_severity[@]}"; do
  if $first && [ "$sev" -eq 1 ]; then 
    performance_flag=1
    first=false
  fi
  ((i++))
done

echo "$performance_flag" > "$tmp_dir/pflag.txt"

if "$do_detailed_report"; then

  # For each location with discomfort, dump data for each metric during occupied hours into separate file for graphing.
  i0_result=0
  for i1_zone in "${array_zones_with_MRTsensors[@]}"; do
    i0_zone="$((i1_zone-1))"
    zone_name=${array_zone_names[i0_zone]}

    # There are CFD results, one for each sensor.
    if "$is_CFD" && ${array_use_CFDresults[i0_zone]}; then
      zone_sensor_names="$(awk -v zoneNum="$i1_zone" -f "$common_dir/esp-query/processOutput_getSpaceSeparatedZoneMRTsensorNames.awk" "$tmp_dir/query_results.txt")"
      array_zone_sensor_names=($zone_sensor_names)
      for sensor_name in "${array_zone_sensor_names[@]}"; do
        if [ "${array_severity[i0_result]}" -gt 0 ]; then
          i1_result="$((i0_result+1))"
          i=1
          output="$(awk -v zone="$i1_result" -v recursion="$i" -f "$script_dir/get_singleZoneAllRecursive.awk" "$tmp_dir/CO2.txt")"
          while [ ! "X$output" == "X" ]; do
            echo "$output" > "$tmp_dir/res$i1_result-$i"
            ((i++))    
            output="$(awk -v zone="$i1_result" -v recursion="$i" -f "$script_dir/get_singleZoneAllRecursive.awk" "$tmp_dir/CO2.txt")"
          done
          array_num_plotFiles[i0_result]="$((i-1))"
        else
          array_num_plotFiles[i0_result]=0
        fi
        ((i0_result++))
      done
    
    # There is just a single zone-averaged result.
    else
      if [ "${array_severity[i0_result]}" -gt 0 ]; then
        i1_result="$((i0_result+1))"
        i=1
        output="$(awk -v zone="$i1_result" -v recursion="$i" -f "$script_dir/get_singleZoneAllRecursive.awk" "$tmp_dir/CO2.txt")"
        while [ ! "X$output" == "X" ]; do
          echo "$output" > "$tmp_dir/res$i1_result-$i"
          ((i++))    
          output="$(awk -v zone="$i1_result" -v recursion="$i" -f "$script_dir/get_singleZoneAllRecursive.awk" "$tmp_dir/CO2.txt")"
        done
        array_num_plotFiles[i0_result]="$((i-1))"
      else
        array_num_plotFiles[i0_result]=0
      fi
      ((i0_result++))
    fi
  done
fi

# Update progress file.
echo '6' > "$tmp_dir/progress.txt"



# *** Write JSON file ***

echo '{' > "$JSON"

# If there is any discomfort, write directives.
if [ "$performance_flag" -gt 0 ]; then
  echo "  \"poor air quality\": [" >> "$JSON"
  first=true
  i0_result=0
  for i1_zone in "${array_zones_with_MRTsensors[@]}"; do
    i0_zone="$((i1_zone-1))"
    zone_name=${array_zone_names[i0_zone]}

# There are CFD results, one for each sensor.
    if "$is_CFD" && ${array_use_CFDresults[i0_zone]}; then
      zone_sensor_names="$(awk -v zoneNum="$i1_zone" -f "$common_dir/esp-query/processOutput_getSpaceSeparatedZoneMRTsensorNames.awk" "$tmp_dir/query_results.txt")"
      array_zone_sensor_names=($zone_sensor_names)
      for sensor_name in "${array_zone_sensor_names[@]}"; do
#      while [ "$i0_zone_sensor" -lt "${array_MRT_sensors[i0_zone]}" ]; do
        if [ "${array_severity[i0_result]}" -gt 0 ]; then          
          if $first; then
            first=false
          else
            echo "," >> "$JSON"
          fi
          echo '    {' >> "$JSON"
          echo "      \"area\": \"$zone_name\"," >> "$JSON"
          echo "      \"location\": \"$sensor_name\"," >> "$JSON"
          echo "      \"CO2 concentration\": {" >> "$JSON"
          echo "        \"frequency of occurrence (%)\": \"${array_PTD[i0_result]}\"," >> "$JSON"
          i1_result="$((i0_result+1))"
          x="$(awk -v entryNum="$i1_result" -f "$script_dir/get_sensorStats.awk" "$tmp_dir/CO2summary.txt")"
          a=($x)
          s="${a[0]}/${a[1]}/$year @ ${a[2]}"
          echo "        \"worst time\": \"$s\"" >> "$JSON"
          echo "      }" >> "$JSON"
          printf '    }' >> "$JSON"
        fi
#        ((i0_zone_sensor++))
        ((i0_result++))
      done
    else

# There is just a single zone-averaged result.
# However to maintain consistency, we still write out a directive for each location.
      PTD="${array_PTD[i0_result]}"
      severity="${array_severity[i0_result]}"
      i1_result="$((i0_result+1))"
      x="$(awk -v entryNum="$i1_result" -f "$script_dir/get_sensorStats.awk" "$tmp_dir/CO2summary.txt")"
      a=($x)
      worst_time="${a[0]}/${a[1]}/$year @ ${a[2]}"
#      while [ "$i0_zone_sensor" -lt "${array_MRT_sensors[i0_zone]}" ]; do

      zone_sensor_names="$(awk -v zoneNum="$i1_zone" -f "$common_dir/esp-query/processOutput_getSpaceSeparatedZoneMRTsensorNames.awk" "$tmp_dir/query_results.txt")"
      array_zone_sensor_names=($zone_sensor_names)
      for sensor_name in "${array_zone_sensor_names[@]}"; do

        if [ "$severity" -gt 0 ]; then          
          if $first; then
            first=false
          else
            echo "," >> "$JSON"
          fi
          echo '    {' >> "$JSON"
          echo "      \"area\": \"$zone_name\"," >> "$JSON"
          echo "      \"location\": \"$sensor_name\"," >> "$JSON"
          echo "      \"CO2 concentration\": {" >> "$JSON"
          echo "        \"frequency of occurrence (%)\": \"$PTD\"," >> "$JSON"
          echo "        \"worst time\": \"$worst_time\"" >> "$JSON"
          echo "      }" >> "$JSON"
          printf '    }' >> "$JSON"
        fi
#        ((i0_zone_sensor++))
      done
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
  echo '\usepackage{fontspec}' >> "$report"
  echo '\setmainfont{TeX Gyre Termes}' >> "$report"
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
  #echo '\begin{landscape}' >> "$detailed_report"
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
    echo 'The table lists rank-ordered assessment results for locations that do not comply with the standard.' >> "$detailed_report"
    echo 'Next, comfort parameter values at locations that do not comply with the standard are shown, with criteria from the standard as dashed lines.' >> "$detailed_report"
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
  echo '\multirow{4}{*}{Area} & \multirow{4}{*}{Location} & \multirow{4}{3cm}{\centering{Frequency of CO\textsubscript{2}\\concentration\\violating criteria\\(\%)}} & \multirow{4}{4cm}{\centering{Time of worst\\criteria violation\\(MM/DD HH:MM)}} \\' >> "$report"
  echo ' \\' >> "$report"
  echo ' \\' >> "$report"
  echo ' \\' >> "$report"
  echo '\hline' >> "$report"
  echo '\endfirsthead' >> "$report"
  echo '' >> "$report"
  echo '\hline' >> "$report"
  echo '\multicolumn{4}{l}{\small\sl continued from previous page} \\' >> "$report"  
  echo '\hline' >> "$report"
  echo '\multirow{4}{*}{Area} & \multirow{4}{*}{Location} & \multirow{4}{3cm}{\centering{Frequency of CO\textsubscript{2}\\concentration\\violating criteria\\(\%)}} & \multirow{4}{4cm}{\centering{Time of worst\\criteria violation\\(MM/DD HH:MM)}} \\' >> "$report"
  echo ' \\' >> "$report"
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
    echo '\multirow{4}{*}{Area} & \multirow{4}{*}{Location} & \multirow{4}{3cm}{\centering{Frequency of CO\textsubscript{2}\\concentration\\violating criteria\\(\%)}} & \multirow{4}{4cm}{\centering{Time of worst\\criteria violation\\(MM/DD HH:MM)}} \\' >> "$detailed_report"
    echo ' \\' >> "$detailed_report"
    echo ' \\' >> "$detailed_report"
    echo ' \\' >> "$detailed_report"
    echo '\hline' >> "$detailed_report"
    echo '\endfirsthead' >> "$detailed_report"
    echo '' >> "$detailed_report"
    echo '\hline' >> "$detailed_report"
    echo '\multicolumn{4}{l}{\small\sl continued from previous page} \\' >> "$detailed_report"  
    echo '\hline' >> "$detailed_report"
    echo '\multirow{4}{*}{Area} & \multirow{4}{*}{Location} & \multirow{4}{3cm}{\centering{Frequency of CO\textsubscript{2}\\concentration\\violating criteria\\(\%)}} & \multirow{4}{4cm}{\centering{Time of worst\\criteria violation\\(MM/DD HH:MM)}} \\' >> "$detailed_report"
    echo ' \\' >> "$detailed_report"
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
  for i1_zone in "${array_zones_with_MRTsensors[@]}"; do
    i0_zone="$((i1_zone-1))"
    zone_name=${array_zone_names[i0_zone]}

# There are CFD results, one for each sensor.
    if "$is_CFD" && ${array_use_CFDresults[i0_zone]}; then
      zone_sensor_names="$(awk -v zoneNum="$i1_zone" -f "$common_dir/esp-query/processOutput_getSpaceSeparatedZoneMRTsensorNames.awk" "$tmp_dir/query_results.txt")"
      array_zone_sensor_names=($zone_sensor_names)
      for sensor_name in "${array_zone_sensor_names[@]}"; do
        if [ "${array_severity[i0_result]}" -gt 0 ]; then
          i1_result="$((i0_result+1))"
          x="$(awk -v entryNum="$i1_result" -f "$script_dir/get_sensorStats.awk" "$tmp_dir/CO2summary.txt")"
          a=($x)
          worst_time="${a[1]}/${a[0]} ${a[2]}"
          echo "$zone_name & $sensor_name & \\hfil ${array_PTD[i0_result]} & \\hfil ${worst_time} "'\\' >> "$tmp_dir/PTD_table"
        fi
        ((i0_result++))
      done
    else

# There is just a single zone-averaged result.
# However to maintain consistency, we still write out a table entry for each location.
      PTD="${array_PTD[i0_result]}"
      severity="${array_severity[i0_result]}"
      i1_result="$((i0_result+1))"
      x="$(awk -v entryNum="$i1_result" -f "$script_dir/get_sensorStats.awk" "$tmp_dir/CO2summary.txt")"
      a=($x)
      worst_time="${a[1]}/${a[0]} ${a[2]}"
      zone_sensor_names="$(awk -v zoneNum="$i1_zone" -f "$common_dir/esp-query/processOutput_getSpaceSeparatedZoneMRTsensorNames.awk" "$tmp_dir/query_results.txt")"
      array_zone_sensor_names=($zone_sensor_names)
      for sensor_name in "${array_zone_sensor_names[@]}"; do
        if [ "$severity" -gt 0 ]; then
          echo "$zone_name & $sensor_name & \\hfil $PTD & \\hfil $worst_time "'\\' >> "$tmp_dir/PTD_table"
        fi
      done
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

    timebase="$(awk -f "$script_dir/get_timebase.awk" "$tmp_dir/CO2.txt")"
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
    echo 'ylabel={CO\textsubscript{2} concentration (PPM)},' >> "$detailed_report"
    echo ']' >> "$detailed_report"

    # Loop over sensors with discomfort.
    i0_result=0
    i0_zone=-1
    i0_colour=-1
    legend=''
    for i1_zone in "${array_zones_with_MRTsensors[@]}"; do
      i0_zone_prev="$i0_zone"
      i0_zone="$((i1_zone-1))"
      zone_name=${array_zone_names[i0_zone]}

      # Set colour by zone.
      if [ "$i0_zone" -gt "$i0_zone_prev" ]; then 
        ((i0_colour++))
      fi

      # There are CFD results, one for each sensor.
      if "$is_CFD" && ${array_use_CFDresults[i0_zone]}; then
        zone_sensor_names="$(awk -v zoneNum="$i1_zone" -f "$common_dir/esp-query/processOutput_getSpaceSeparatedZoneMRTsensorNames.awk" "$tmp_dir/query_results.txt")"
        array_zone_sensor_names=($zone_sensor_names)
        i0_mark=-1
        for sensor_name in "${array_zone_sensor_names[@]}"; do

          # Set mark by sensor.
          ((i0_mark++))
          if [ "${array_severity[i0_result]}" -gt 0 ]; then
            i1_result="$((i0_result+1))"
            
            # Add a plot for each occupied period.
            i=1
            while [ "$i" -le "${array_num_plotFiles[i0_result]}" ]; do
              echo '\addplot['"color=${array_pgfColours[i0_colour]},mark=${array_pgfMarks[i0_mark]}"'] table [' >> "$detailed_report"
              if [ $num_sim_days -gt 7 ]; then
                echo 'x expr=(\thisrowno{0}-'"$timebase"'),' >> "$detailed_report"
              else
                echo 'x expr=(\thisrowno{0}-'"$timebase"')*24,' >> "$detailed_report"
              fi

              # Change units from g/kg to PPM
              echo 'y expr={\thisrowno{1}*1000.0},' >> "$detailed_report"
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
        done
      else

        # There is just a single zone-averaged result.
        # However to maintain consistency, we still add a plot for each location.
        severity="${array_severity[i0_result]}"
        i1_result="$((i0_result+1))"
        zone_sensor_names="$(awk -v zoneNum="$i1_zone" -f "$common_dir/esp-query/processOutput_getSpaceSeparatedZoneMRTsensorNames.awk" "$tmp_dir/query_results.txt")"
        array_zone_sensor_names=($zone_sensor_names)
        i0_mark=-1
        for sensor_name in "${array_zone_sensor_names[@]}"; do

          # Set mark by sensor.
          ((i0_mark++))
          if [ "$severity" -gt 0 ]; then

            # Add a plot for each occupied period.
            i=1
            while [ "$i" -le "${array_num_plotFiles[i0_result]}" ]; do
              echo '\addplot['"color=${array_pgfColours[i0_colour]},mark=${array_pgfMarks[i0_mark]}"'] table [' >> "$detailed_report"
              if [ $num_sim_days -gt 7 ]; then
                echo 'x expr=(\thisrowno{0}-'"$timebase"'),' >> "$detailed_report"
              else
                echo 'x expr=(\thisrowno{0}-'"$timebase"')*24,' >> "$detailed_report"
              fi

              # Change units from g/kg to PPM
              echo 'y expr={\thisrowno{1}*1000.0},' >> "$detailed_report"
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
        done
        ((i0_result++))
      fi    
    done

    # Define discomfort criteria line.
    echo '\addplot[black, dashed, samples=2, domain='"$xmin:$xmax"'] {'"$ppm_mass_criteria"'};' >> "$detailed_report"

    echo '\legend{'"${legend:0:$num_commas}"'}' >> "$detailed_report"

    echo '\end{axis}' >> "$detailed_report"
    echo '\end{tikzpicture}' >> "$detailed_report"
    echo '\end{figure}' >> "$detailed_report"
    echo '' >> "$detailed_report"

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
lualatex -halt-on-error -output-directory="$tmp_dir" "$report" > "$tmp_dir/lualatex.out"
lualatex -halt-on-error -output-directory="$tmp_dir" "$report" >> "$tmp_dir/lualatex.out"
lualatex -halt-on-error -output-directory="$tmp_dir" "$report" >> "$tmp_dir/lualatex.out"
mv "${report:0:-4}.pdf" "$report_final"

if "$do_detailed_report"; then
  if $verbose; then echo " Generating detailed pdf report ..."; fi
  echo >> "$detailed_report"
  #echo '\end{landscape}' >> "$detailed_report"
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

if $verbose; then 
  echo " Done"
  echo
  echo "***** 15251 PAM END"
fi
