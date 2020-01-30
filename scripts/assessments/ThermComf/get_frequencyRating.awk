# Outputs:
# "no zones" - 0
# "one zone" - 1
# "few zones" - <25%
# "several zones" - <50%
# "many zones" - >=50%
# "all zones"

# looks for input argument "severity".
# if severity is "discomfort", will look for both "severe" and "moderate".

BEGIN {
# Default severity keyword = "none"
  if (severity=="") {severity="none"}
  count=0
}

{
  for (i=1;i<=NF;i++) {
    if (count==0) {n=NF}
    if (severity=="discomfort") {if ($i=="severe" || $i=="moderate") {count++}}
    else {if ($i==severity) {count++}}
  }
}

END {
  few=n/4
  several=n/2
  if (count==0) {print "no zones"}
  else if (count==1) {print "one zone"}
  else if (count<few) {print "few zones"}
  else if (count<=several) {print "several zones"}
  else if (count<n) {print "most zones"}
  else if (count==n) {print "all zones"}
  else {print "ERROR"}  
}
