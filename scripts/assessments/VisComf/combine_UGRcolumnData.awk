BEGIN {
  col=0
  numlines=0
  numtimes=0
}

{
  line=FNR
  if (line>numlines) {
    numlines=line
  }
  if (line==1) {
    col+=1
    numcols=col
  }
  found=0
  if (numtimes>0) {
    for (x=1;x<=numtimes;x++) {
      if ($1==times[x]) {
        found=1
        break
      }
    }
  }
  if (!found) {
    numtimes+=1
    times[numtimes]=$1
  }
  s[$1,col]=$2
}

END {
  n=asort(times)
  for (x in times) {
    for (y=1;y<=numcols;y++) {
      if (y==1) {
        printf times[x]
      }
      if (s[times[x],y]=="") {
        printf " not_occ"
      } else {
        printf " "s[times[x],y]
      }
    }
    printf "\n"
  }
}
      
    
