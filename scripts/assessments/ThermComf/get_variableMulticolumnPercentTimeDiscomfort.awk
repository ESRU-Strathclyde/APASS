BEGIN {
  first=1
  n=0
  ORS=" "
  if (ncols=="") {
    ncols=1
  }
  lenncolarr=split(ncols,ncolarr,",")
}

{ 
  if ($0==" ") {exit}

  ioutcol=0
  i=0

# Loop over all ncols.
  for (incol in ncolarr) {
    ncols=ncolarr[incol]

# If ncols is 0, there are no occupant locations in the first zone.
# On the first line, add a column with countTot=0 (this will result in a not_occ output).
# On subsequent lines, just skip over this column.
    if (ncols<=0) {
      ioutcol++
      if (first==1) {
        countTot[ioutcol]=0
        countDscft[ioutcol]=0
        n++
      }
    }

# ncols is greater than 0, so we loop over that many columns and find the maximum of those.
    else {
      max="-"
      for (j=0;j<ncols;j++) {
        i++
        val=$i
#        print val
        if (max=="-") {
          if (val!="-") {max=val}
        }
        else if (max=="x") {
          if (val!="-" && val!="x") {max=val}
        }
        else {
          if (val>max) {max=val}
        }
      }

      ioutcol++
      if (first==1) {
        countTot[ioutcol]=0
        countDscft[ioutcol]=0
        n++
      }
      if (max!="-") {
#        print "X" "TOT+ c" ioutcol "X"
        countTot[ioutcol]++
        if (max!="x") {
#          print "X" "DSCF+ c" ioutcol "X"
          countDscft[ioutcol]++
        }
      }
    }
  }
  if (first==1) {
    first=0
  }
  #print "\n"
}

END {
  for (i=1;i<=n;i++) {
    if (countTot[i]>0) {
#      print "X"countDscft[i]"X" "X"countTot[i]"X" "\n"
      pct=countDscft[i]/countTot[i]*100
      printf "%.1f ", pct
    }
    else {
      printf "not_occ "
    }
  }
}
