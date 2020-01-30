BEGIN {
  first=1
  n=0
}

{
  if (first==1) {
    n=NF
    first=0
  }  
  for (i=1;i<=NF;i++) {
    if ($i!="-") {
      if ($i!="x") {
        countTot[i]++
        if ($i>0) {countHot[i]++}
      }
    }
  }
}

END {
  ORS=" "
  for (i=1;i<=n;i++) {
    if (countTot[i]>0) {
      pct=countHot[i]/countTot[i]*100
      printf "%.0f ", pct
    }
    else {
      printf "0 "
    }
  }
}
