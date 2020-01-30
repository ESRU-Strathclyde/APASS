BEGIN {
  first=1
}

{
  if ($0=="                       value    occurrence    value    occurrence     value  deviation") {active=1}
  else if (active==1) {
    if (NF==0) {
      zone=0
      active=0
      next
    }
    zone++
    if ($3=="No" && $4=="data:") {next}
    max=$3
    abs_max=sqrt(max^2)
    min=$5
    abs_min=sqrt(min^2)
    if (abs_max<abs_min) {
      abs_max=abs_min
      max_day=$6
    }
    else {
      max_day=$4
    }    
    if (first==1) {
      worst=abs_max
      worstZone=zone
      worstDay=substr(max_day,1,6)
      worstTime=substr(max_day,8,5)
      first=0
    }
    else {
      if (abs_max>worst) {
        worst=abs_max
        worstZone=zone
        worstDay=substr(max_day,1,6)
        worstTime=substr(max_day,8,5)
      }
    }
  }
}

END {
  print worstZone,worstDay,worst,worstTime
}
