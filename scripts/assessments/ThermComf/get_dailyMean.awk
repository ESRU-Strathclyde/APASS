BEGIN {
  curday=0;
  ORS=" ";
}

{
	if (substr($1,1,1)=="#") {next}
  split($1,a,".");
  day=a[1];
  if (day>curday) {
    if (curday>0) {
      print(curday);
      for (i in n) {
        if (n[i]>0) {
          printf("%.2f ",tot[i]/n[i]);
        }
        else {
          printf("not_occ ");
        }
        n[i]=0;
        tot[i]=0.0;
      }
      print("\n");
    }
    curday=day;
  }
  j=0;
  for (i=2;i<=NF;i++) {
    j++;
    if ($i=="not") {
      i++;
      continue;
    }
    n[j]++;
    tot[j]+=$i;
  }
}

END {  
  print(day);
  for (i in n) {
    if (n[i]>0) {
      printf("%.2f ",tot[i]/n[i]);
    }
    else {
      printf("not_occ ");
    }
  }
}