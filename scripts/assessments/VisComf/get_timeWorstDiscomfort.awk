BEGIN {
  first=1;
  n=0;
}

{
  for (i=2;i<=NF;i++) {
    if (first==1) {
      maxs[i]=0;
      maxtimes[i]="";
      n++;
    }
    if ($i!="failed" && $i!="not_occ") {
      if ($i>maxs[i]) {
        maxs[i]=$i;
        maxtimes[i]=$1;
      }
    }
  }
  if (first==1) {
    first=0;
  }  
}

END {
  for (i in maxtimes) {
    t=(maxtimes[i]-int(maxtimes[i]))*24;
    tm=(t-int(t))*60;
    if (sprintf("%02.0f",tm)=="60") {
      th=int(t);
      tm=0.0;
    }
    else {
      th=int(t)-1;
    }
    printf("%d_%02d:%02.0f ",int(maxtimes[i]),th,tm);
  }
}
