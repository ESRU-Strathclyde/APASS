BEGIN {
  first=1
  # default criteria: 1.0
  if (criteria=="") {criteria=1.0}
}

{
  if (first==0) {
    optimum=$2
  }

	for (i=3;i<=NF;i++) {

    # Compare current values with previous.      
    if (first==0) {
      if ($i!="not_occ" && prevVals[i]!="not_occ") {
        if (sqrt(($i-optimum)^2) > sqrt(($prevVals[i]-optimum)^2)) {
          drift=sqrt(($i-prevVals[i])^2)
          if (drift>criteria) {dscft[i]++}
        }
        n[i]++
      }
    }

    # Set previous values to current
    prevVals[i]=$i

  }
  if (first==1) {first=0}
}

END {
  for (i in n) {
    printf("%.1f ",(dscft[i]/n[i]*100.0))
  }
}