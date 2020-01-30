BEGIN {
  first=1
}

{
  if (first==1) {print $0}
  if ($0=="                       value    occurrence    value    occurrence     value  deviation") {
    active=1
    first=0
  }
  else if (active==1) {
    if ($0=="(above data filtered by occupancy)") {
      active=0
      first=0
    }
    else {print $0}
  }
}

END {
  print "\n[dummy line]"
}
      
    
