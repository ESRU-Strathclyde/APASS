BEGIN {
  first=1
  n=0
}

{
  for (i=2;i<=NF;i++) {
    if (first==1) {
      maxs[i]=0
      maxtimes[i]=""
      n++
    }
    if ($i>maxs[i]) {
      maxs[i]=$i
      maxtimes[i]=$1
    }
  }
  if (first==1) {
    first=0
  }  
}

END {
  for (i in maxtimes) {
    printf int(maxtimes[i])"_"(maxtimes[i]-int(maxtimes[i]))*24
  }
}
