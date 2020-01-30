BEGIN {
# Default zone = 1
  if (zone=="") {zone=1}
  col=zone+1;
# Default recursion = 1
  if (recursion=="") {recursion=1}
  active=0;
  toggle=0;
}

{
  if (substr($1,1,1)=="#") {next}
  j=1;
  for (i=2;i<=NF;i++) {
    j++;

    if (j==col) {
      if ($i !~ /^-?[0-9]+\.?[0-9]*$/) {
        if (toggle) {
          if (!recursion) {exit}
          toggle=0;
        }
        continue;
      }
      else {
        if (!toggle) {
          toggle=1;
          recursion--;
          if (!recursion) {active=1}
        }
        if (active) {print $1,$i}
      }
    }
    if ($i == "not" || $i == "no" || $i == "invl") {
      i++;
    }
  }
}
