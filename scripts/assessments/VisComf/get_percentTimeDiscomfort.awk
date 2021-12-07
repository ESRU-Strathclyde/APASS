# Inputs:
# criteria

# Outputs:
# -1: not occupied
# 0: compliant
# 1: non-compliant

BEGIN {
  first=1
  n=0
}

{
  for (i=1;i<=NF;i++) {
    if (first==1) {
      countTot[i]=0
      countDscft[i]=0
      countFailed[i]=0
      countNotOcc[i]=0
      n++
    }
    countTot[i]++
    if ($i=="f") {countFailed[i]++}
    else if ($i=="-") {countNotOcc[i]++}
    else if ($i!="x") {countDscft[i]++}
  }
  if (first==1) {
    first=0
  }  
}

END {
  for (i=1;i<=n;i++) {
    if (countTot[i]>0) {
      if (countFailed[i]==countTot[i]) {
        printf "failed "
      }
      if (countNotOcc[i]==countTot[i]) {
        printf "not_occ "
      }
      pct=countDscft[i]/(countTot[i]-countFailed[i])*100
      printf "%.1f ", pct
    }
    else {
      printf "not_occ "
    }
  }
}