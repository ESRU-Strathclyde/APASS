BEGIN {
# default criteria for deviation: 0
  if (criteria=="") {criteria=0}

  ORS=" "
}

{
  if (substr($1,1,1)=="#") {next}
  for (i=2;i<=NF;i++) {
    if ($i ~ /^-?[0-9]+\.?[0-9]*$/) {
      n=sqrt($i^2)
      c=sqrt(criteria^2)
      dif=n-c
      if (dif>0) {
        if (n>0) {print $i-criteria}
        else if (n<0) {print $i+criteria}
      }
      else {
        print "x"
      }
    }
    else {
      if ($i=="not" || $i=="no" || $i=="invl") {i++}
      print "-"
    }
  }
  print "\n"
}
