BEGIN {
# Default zone = 1
  if (zone=="") {zone=1}
  col=zone+1
}

{
  if (substr($1,1,1)=="#") {next}
  j=1
  for (i=2;i<=NF;i++) {
    j++
    if ($i=="not") {
      i++
      continue
    }
    if (j==col) {print $1,$i}
  }
}
