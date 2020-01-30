BEGIN {
  ORS=" "
}

{
  if ($0=="Description Max_value Max_occur Min_value Min_occur Ave_value Std_dev") {active=1}
  else if (active==1) {
    if (NF==0) {exit}
    if ($2=="No" && $3=="data:") {
      print "NoData"
      next
    }
    print $2,substr($3,1,6),substr($3,8,5)
  }
}
