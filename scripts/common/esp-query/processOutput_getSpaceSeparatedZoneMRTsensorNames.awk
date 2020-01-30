BEGIN {
  FS="="
  active=0
  ORS=" "
  s="  zone#"zoneNum
}

{

  if (active==1) {    
    if ($0=="") {exit}
    if ($1==s) {
      split($2,arr,",")
      for (i in arr) {
        print arr[i]
      }
      exit
    }
  }
  if ($1=="MRT_sensor_names:") {active=1}
}
