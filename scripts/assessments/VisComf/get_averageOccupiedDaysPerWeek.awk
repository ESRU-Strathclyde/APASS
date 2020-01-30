BEGIN {
  hour_counter=1
  day_counter=1
  week_counter=0
  first=1
  if (timesteps=="") {timesteps=1}
  timestep_counter=0
}

{
  if (substr($1,1,1)=="#") {next}
  timestep_counter++
  if (timestep_counter>timesteps) {
    timestep_counter=1
    hour_counter++
  }
  if (hour_counter>24) {
    hour_counter=1
    day_counter++
    for (i in todayDone_flags) {
      todayDone_flags[i]=0
    }
  }
  if (day_counter>7) {
    day_counter=1
    week_counter++
    for (i in occDay_counters) {
      aggOccDays[i]=aggOccDays[i]+occDay_counters[i]
      occDay_counters[i]=0
    }
  }
  j=0
  for (i=2;i<=NF;i++) {
    j++
    if (first==1) {
      occDay_counters[j]=0
      aggOccDays[j]=0
      first=0
    }
    if ($i=="not") {
      i++
    }
    else {
      if (todayDone_flags[j]==0) {
        todayDone_flags[j]=1
        occDay_counters[j]++
      }
    }
  }
}

END {
  ORS=" "
  if (week_counter>0) {
    for (i in aggOccDays) {
#      print aggOccDays[i]
#      print week_counter
      print aggOccDays[i]/week_counter
    }
  }
  else {
    for (i in occDay_counters) {
      print occDay_counters[i]
    }
  }
}
