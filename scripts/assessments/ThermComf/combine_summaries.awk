BEGIN {
  first=1
}

{
  if (first==1) {print $0}
  if ($0=="Description Max_value Max_occur Min_value Min_occur Ave_value Std_dev") {
    active=1
    first=0
  }
  else if (active==1) {
    if (NF==0) {
      active=0
      first=0
    }
    else {print $0}
  }
}

END {
  print "\n[dummy line]"
}
      
    
