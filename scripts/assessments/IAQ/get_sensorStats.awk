BEGIN {
  if (zoneName=="" && sensorName=="") {
    if (entryNum=="") {exit}
    mode=2
    i=1
  }
  else if (entryNum=="") {
    if (zoneName=="" && sensorName=="") {exit}
    mode=1
    nam=sprintf("%s%s",zoneName,sensorName)
  }
  if (isCFD=="") {exit}

  active=0
  cur_max=0.0
  months["Jan"]=01
  months["Feb"]=02
  months["Mar"]=03
  months["Apr"]=04
  months["May"]=05
  months["Jun"]=06
  months["Jul"]=07
  months["Aug"]=08
  months["Sep"]=09
  months["Oct"]=10
  months["Nov"]=11
  months["Dec"]=12
}

{
  if ($0=="                                   value    occurrence    value    occurrence     value  deviation") {active=1}
  else if (active==1) {
    if (NF==0) {
      active=0
      next
    }
    if ($5=="No" && $6=="data:") {next}

    if (mode==1) {
      if (nam==$1) {
        max=$5
        abs_max=sqrt(max^2)
        min=$7
        abs_min=sqrt(min^2)
        if (abs_max<abs_min) {
          max_day=$8
        }
        else {
          max_day=$6
        }    
        if (abs_max>cur_max) {
          cur_max=abs_max
          cur_maxDay=max_day
        }
        active=0
      }
    }
    else if (mode==2) {
      if (i==entryNum) {
        if (isCFD) {
          max=$3
        } else {
          max=$5
        }
        abs_max=sqrt(max^2)
        if (isCFD) {
          min=$5
        } else {
          min=$7
        }
        abs_min=sqrt(min^2)
        if (abs_max<abs_min) {
          if (isCFD) {
            max_day=$6
          } else {
            max_day=$8
          }
        }
        else {
          if (isCFD) {
            max_day=$4
          } else {
            max_day=$6
          }
        }    
        if (abs_max>cur_max) {
          cur_max=abs_max
          cur_maxDay=max_day
        }
        active=0
      }
      i++
    }
  }
}

END {
  worstDay=substr(cur_maxDay,1,2)
  worstMonthStr=substr(cur_maxDay,4,3)
  worstMonth=months[worstMonthStr]
  worstTimeh=substr(cur_maxDay,8,5)
  worstTime=gensub("h",":",1,worstTimeh)
  print worstDay,worstMonth,worstTime
}
