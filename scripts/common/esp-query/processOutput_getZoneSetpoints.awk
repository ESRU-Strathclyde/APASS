BEGIN {
  found=0
}

{
  if ($1=="zone_setpoints:") {
    found=1
  }

# Read until a blank line is found.
  if (found==1) {
    if ($0=="") {exit}
    print $0
  }
}
