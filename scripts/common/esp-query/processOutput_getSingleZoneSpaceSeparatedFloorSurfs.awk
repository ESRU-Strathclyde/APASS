BEGIN {
  active=0
  ORS=" "
  if (zone=="") {zone=1}
}

{
  split($1,arr,"=")
  if (active==1) {  
    if (arr[1]=="zone#"zone) {
      split(arr[2],arrr,",")
      for (a in arrr) {
      	print arrr[a]
      }
      exit
    }
  }
  if (arr[1]=="zone_floor_surfs:") {active=1}
}
