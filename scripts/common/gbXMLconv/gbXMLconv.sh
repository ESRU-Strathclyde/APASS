#! /bin/bash

# Set up defaults.
information=false
debugDir=""
zipName=""

# Parse command line.
while getopts ":hd:z:" opt; do
  case "$opt" in
    h) information=true;;
    d) debugDir="$OPTARG";;
    z) zipName="$OPTARG";;
    \?) echo "Error: unknown option -$OPTARG. Use option -h for help." >&2
        exit 107;;
    :) echo "Error: option -$OPTARG requires and argument." >&2
       exit 107;;
  esac
done
shift $((OPTIND-1))

if "$information"; then
  echo
  echo " Usage: ./gbXMLconv.sh [OPTIONS] gbXML_file"
  echo
  echo " Converts a gbXML file into an ESP-r model."
  echo
  echo " Command line options: -h"
  echo "                          display help text and exit"
  echo "                          default: off"
  echo "                       -d out_dir"
  echo "                          output debug information in out_dir/???.out files"
  echo "                          default: off"
  echo "                       -z zip_file"
  echo "                          place model in archive zip_file"
  echo "                          default: off"

  exit 0
fi

if [ ! "X$debugDir" == "X" ]; then
  debugDir="$(readlink -f "$debugDir")"
fi

# Get encoding of file.
encoding="$(file -b --mime-encoding "$1")"
if [ "X$encoding" == "X" ]; then
  echo "Error: could not detect gbXML file encoding." >&2
  exit 1
fi

# Convert to ascii.
rootName="${1%.*}"
rootDir="$(dirname "$1")"
convName="${rootName}_ascii.xml"
if [[ ! "$encoding" == "*ascii*" ]]; then
  if [ ! "X$debugDir" == "X" ]; then
    out="$debugDir/gbXMLconv_iconv.out"
  else
    out="/dev/null"
  fi
  iconv -c -f "$encoding" -t ascii -o "$convName" "$1" > "$out"
#  iconv -c -f "$encoding" -t ascii -o "$convName" "$1"
  if [ ! -f "$convName" ]; then
    echo "Error: could not convert gbXML file to ascii." >&2
    exit 1
  fi
fi

# Run conversion.
curDir="$(echo "$PWD")"
convBase="$(basename "$convName")"
rootBase="$(basename "$rootName")"
modelBase="${rootBase}_model"
cd "$rootDir"
rm -rf "$modelBase" > /dev/null
if [ ! "X$debugDir" == "X" ]; then
  out="$debugDir/gbXMLconv_ecnv.out"
else
  out="/dev/null"
fi
ecnv -if gbxml -in "$convBase" -of esp -out "$modelBase" > "$out" << XXX
#ecnv -if gbxml -in "$convBase" -of esp -out "$modelBase" << XXX
e
XXX
cd "$curDir"
modelName="${rootName}_model"
if [ ! $# -eq 0 ] && [ ! -d "$modelName" ]; then
  echo "Error: could not convert gbXML file to ESP-r model." >&2
  exit 1
fi

# Zip up model, if requested.
if [ ! "X$zipName" == "X" ]; then
  rm -f "$zipName" > /dev/null
  if [ ! "X$debugDir" == "X" ]; then
    out="$debugDir/gbXMLconv_zip.out"
  else
    out="/dev/null"
  fi
  zip -r "$zipName" "$modelName" > "$out"
  if [ ! -f "$zipName" ]; then
    echo "Error: could not zip up ESP-r model." >&2
    exit 1
  fi
fi
