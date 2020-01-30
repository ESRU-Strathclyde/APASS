BEGIN {
# Default column = 2
  if (col=="") {col=2}
}

{
  if (substr($1,1,1)=="#") {next}
  j=1;
  for (i=2;i<=NF;i++) {
    j++;
    if (j==col) {
      if ($i == "not" || $i == "no" || $i == "invl") {
        k=i+1;
        print $i,$k;
        i++;
      }
      else {
        print $i;
      }
    }
  }
}
