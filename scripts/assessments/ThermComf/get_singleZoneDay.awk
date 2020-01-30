BEGIN {
# Default zone = 1
  if (zone=="") {zone=1}
  col=zone+1
# Default day = 1
  if (day=="") {day=1}
}

{
  if (substr($1,1,1)=="#") {next}
  if ($1>=day) {
    if ($1>=day+1) {exit}
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
}
