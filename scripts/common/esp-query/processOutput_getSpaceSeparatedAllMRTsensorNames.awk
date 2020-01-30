BEGIN {
  FS="="
  active=0
  ORS=" "
}

{
  if (active==1) {    
    if ($0=="") {exit}
    split($2,arr,",")
    for (i in arr) {
      print arr[i]
    }
  }
  if ($1=="MRT_sensor_names:") {active=1}
}
