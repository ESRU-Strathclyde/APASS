#! /bin/bash

# Dummy PAM to generate a wireframe image of an ESP-r model in pdf format.

# Set up defaults.
building=""
tmp_dir="./tmp"
information=false
verbose=false
model_image="./pic.jpg"
JSON="./data.json"

# Parse command line.
while getopts ":hvd:r:j:" opt; do
  case "$opt" in
    h) information=true;;
    v) verbose=true;;
    d) tmp_dir="$OPTARG";;
    r) model_image="$OPTARG";;
    j) JSON="$OPTARG";;
    \?) echo "Error: unknown option -$OPTARG. Use option -h for help." >&2
        exit 107;;
    :) echo "Error: option -$OPTARG requires and argument." >&2
       exit 107;;
  esac
done
shift $((OPTIND-1))
building="$1"

if [ "X$building" == "X" ]; then
  echo "Error: no input model specified." >&2
  exit 107
fi

# Test if model cfg file exists.
if ! [ -f "$building" ]; then
  echo "Error: model cfg file could not be found." >&2
  exit 107
fi

dateTime="$(date -u)"

if "$information" ; then
  echo
  echo " Usage: ./wireframe.sh [-h] model-cfg-file"
  echo
  echo " Dummy PAM that generates a .jpg wireframe image of an ESP-r model."
  echo
  echo " Command line options: -h"
  echo "                          display help text and exit"
  echo "                          default: off"
  echo "                       -v"
  echo "                          verbose output to stdout"
  echo "                          default: off"
  echo "                       -j JSON-file"
  echo "                          file name of the json report"
  echo "                          default: ./data.json"
  echo "                       -r wireframe_jpg"
  echo "                          file name of the wireframe jpeg image"
  echo "                          default: ./pic.jpg"
  echo "                       -d temporary-files-directory"
  echo "                          directory into which temporary files will be placed"
  echo "                          default: ./tmp"

  exit 0
fi

# Test if tmp directory exists.
if ! [ -d "$tmp_dir" ]; then
  mkdir "$tmp_dir"
  if ! [ -d "$tmp_dir" ]; then
    echo "Error: could not create temporary files directory." >&2
    exit 1
  fi
fi

# ESP-r seems to have problems if locations have a dot in
# front of them; check for this and remove it.
if [ "${tmp_dir:0:2}" == "./" ] && ! [ "$tmp_dir" == "./" ]; then
  tmp_dir="${tmp_dir:2}"
fi

# Generate image.
ecnv -if esp -in "$building" -of viewer -out "$tmp_dir/comfort_view.v" > "$tmp_dir/ecnv.out"
if [ ! -f "$tmp_dir/comfort_view.v" ]; then
  echo "Error: failed to generate wireframe view" >&2
  exit 111
fi
viewer -mode script -file "$tmp_dir/comfort_view.v" > "$tmp_dir/viewer.out" <<~

r
f
>
b
${tmp_dir}/comfort_view.ww
t
-
~
if [ ! -f "$tmp_dir/comfort_view.v" ]; then
  echo "Error: failed to generate wireframe ww"  >&2
  exit 111
fi
ecnv -if ww -in "$tmp_dir/comfort_view.ww" -of xfig -out "$tmp_dir/comfort_view.fig" >> "$tmp_dir/ecnv.out"
if [ ! -f "$tmp_dir/comfort_view.v" ]; then
  echo "Error: failed to generate wireframe xfig"  >&2
  exit 111
fi
fig2dev -L jpeg "$tmp_dir/comfort_view.fig" > "$model_image" 

# Check that image has been generated.
if [ $? -gt 0 ] || [ ! -f "$model_image" ]; then
  echo "Error: failed to generate wireframe image" >&2
  exit 111
fi

# Create token json as a log.
echo '{"wireframe": {' > "$JSON"
echo '  "run_dateTime": "'"$dateTime"'"' >> "$JSON"
echo '}}' >> "$JSON"
