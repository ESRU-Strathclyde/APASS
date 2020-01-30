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

  active=0
  cur_max=-10.0
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
  if ($0=="Description Max_value Max_occur Min_value Min_occur Ave_value Std_dev") {active=1}
  else if (active==1) {
    if (NF==0) {
      active=0
      next
    }
    if ($3=="No" && $4=="data:") {next}

    if (mode==1) {
      if (nam==$1) {
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
        if (abs_max>cur_max) {
          cur_max=abs_max
          cur_maxDay=max_day
        }
      }
    }
    else if (mode==2) {
      if (i==entryNum) {
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
        if (abs_max>cur_max) {
          cur_max=abs_max
          cur_maxDay=max_day
        }
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
