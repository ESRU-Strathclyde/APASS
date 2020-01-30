BEGIN {
  first=1
}

{
  if (substr($1,1,1)=="#") {next}
  j=0
  for (i=2;i<=NF;i++) {
    j++
    if ($i=="not") {
      i++
      continue
    }
    if (inits[j]==0) {
      mins[j]=$i
      maxs[j]=$i
      inits[j]=1
    }
    else {
      if ($i<mins[j]) {mins[j]=$i}
      if ($i>maxs[j]) {maxs[j]=$i}
    }
    ns[j]++
    tots[j]+=$i
  }
  if (first==1) {
    n=j
    first=0
  }
}

END {
  for (i=1;i<=n;i++) {
    if (ns[i]==0) {
      print "not_occ"
    }
    else {
      print mins[i], maxs[i], tots[i]/ns[i]
    }
  }
}
