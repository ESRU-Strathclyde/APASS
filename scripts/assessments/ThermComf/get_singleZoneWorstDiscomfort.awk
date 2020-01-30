BEGIN {
  first=1
  if (zone==0) {zone=1} # default zone 1
}

{
  if ($0=="Description Max_value Max_occur Min_value Min_occur Ave_value Std_dev") {active=1}
  else if (active==1) {
    if (NF==0) {
      zoneCount=0
      active=0
    }
    zoneCount++
    if (zoneCount==zone) {
      max=$2
      abs_max=sqrt(max^2)
      min=$4
      abs_min=sqrt(min^2)
      if (abs_max<abs_min) {
        abs_max=abs_min
        max_day=$5
      }
      else {
        max_day=$3
      }    
      if (first==1) {
        worst=abs_max
        worstDay=substr(max_day,1,6)
        worstTime=substr(max_day,8,2)
        first=0
      }
      else {
        if (abs_max>worst) {
          worst=abs_max
          worstDay=substr(max_day,1,6)
          worstTime=substr(max_day,8,2)
        }
      }
    }
  }
}

END {
  print worstDay,worst,worstTime
}
