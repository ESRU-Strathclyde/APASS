#! /bin/bash

xglaresrc "$1/../rad/${2}.hdr" "$1/../rad/${2}.glr"
sleep 0.5
import -window "${2}.hdr" "$3/sen${4}-WD.pdf"
sleep 0.5