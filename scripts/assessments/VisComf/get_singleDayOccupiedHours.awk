# This script reads timestep occupancy data and outputs an array of 
# hourly boolean occupancy flags for a single day for a single zone.

BEGIN {

# Default julian day = 1
  if (jDay=="") {jDay=1}

# Default zone = 1
  if (zone=="") {zone=1}
  col=zone+1

  active=0
}

{
  if ($1=="#Time") {
    active=1
    next
  }
  if (active==1) {
    if (int($1)==jDay) {
      hour=($1-int($1))*24.0
      ihour=int(hour)

      j=2
      for (i=2;i<=NF;i++) {
        if ($i ~ /^-?[0-9]+\.?[0-9]*$/) {
          if (j==col) {hours[ihour]=1}
        }
        else {
          if ($i=="not" || $i=="no" || $i=="invl") {i++}
          if (hours[ihour]=="") {hours[ihour]=0}
        }
        j++
      }

    }
  }
}

END {
  ORS=" "
  for (a in hours) {print hours[a]}
}