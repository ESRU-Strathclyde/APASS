BEGIN {
  first=1
  n=0
}

{
  for (i=1;i<=NF;i++) {
    if (first==1) {
      countTot[i]=0
      countDscft[i]=0
      n++
    }
    if ($i!="-") {
      countTot[i]++
      if ($i!="x") {countDscft[i]++}
    }
  }
  if (first==1) {
    first=0
  }  
}

END {
  for (i=1;i<=n;i++) {
    if (countTot[i]>0) {
      pct=countDscft[i]/countTot[i]*100
      printf "%.1f ", pct
    }
    else {
      printf "not_occ "
    }
  }
}
