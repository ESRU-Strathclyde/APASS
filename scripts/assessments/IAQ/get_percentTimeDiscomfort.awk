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
      countTot[i]++
      if ($i!="x") {countDscft[i]++}
    }
  }
}

END {
  for (i=1;i<=n;i++) {
    if (countTot[i]>0) {
      pct=countDscft[i]/countTot[i]*100
      printf "%.1f ", pct
    }
    else {
      printf "0.0 "
    }
  }
}
