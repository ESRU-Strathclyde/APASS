BEGIN {
  first=1
  n=0
  ORS=" "
  if (ncols=="") {ncols=1}
}

{  
  if ($0==" ") {exit}
  
  icol=0
  ioutcol=0
  max="-"
  for (i=1;i<=NF;i++) {
    icol++
    val=$i
    if (max=="-") {
      if (val!="-") {max=val}
    }
    else if (max=="x") {
      if (val!="-" && val!="x") {max=val}
    }
    else {
      if (val>max) {max=val}
    }

    if (icol==ncols) {
      icol=0
      ioutcol++
      if (first==1) {
        countTot[ioutcol]=0
        countDscft[ioutcol]=0
        n++
      }
      if (max!="-") {
        countTot[ioutcol]++
        if (max!="x") {countDscft[ioutcol]++}
      }
      max="-"
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
