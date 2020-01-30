BEGIN {
# Default columns = 1
  if (cols=="") {a_cols[1]=1}
  else {split(cols,a_cols,",")}
}

{
  s="#";
  if (substr($1,1,1)==s) {next}
  j=1;
  val=-666;
  for (i=2;i<=NF;i++) {
    j++;

    for (ind in a_cols) {
      if (j==a_cols[ind]) {
        if ($i ~ /^-?[0-9]+\.?[0-9]*$/) {
          if ($i>val) {val=$i}
        }
        break;
      }
    }
    if ($i == "not" || $i == "no" || $i == "invl") {
      i++;
    }
  }
  if (val==-666) {val="-"}
  print $1,val
}
