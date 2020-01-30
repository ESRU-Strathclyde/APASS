BEGIN {
  FS="="
  active=0
  ORS=" "
}

{
  if (active==1) {    
    if ($0=="") {exit}
    print $2
  }
  if ($1=="zone_win_surfs:") {active=1}
}
