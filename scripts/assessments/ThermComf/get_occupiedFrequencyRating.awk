# Outputs:
# "no zones" - 0
# "one zone" - 1
# "few zones" - <25%
# "several zones" - <50%
# "many zones" - >=50%
# "all zones"

# looks for input argument "severity".
# if severity is "discomfort", will look for both "severe" and "moderate".
# ignores zones with severity "not_occ".

BEGIN {
# Default severity keyword = "none"
  if (severity=="") {severity="none"}
  count=0
  n=0
}

{
  for (i=1;i<=NF;i++) {
    if ($i!="not_occ") {n++}
    if (severity=="discomfort") {if ($i=="severe" || $i=="moderate") {count++}}
    else {if ($i==severity) {count++}}
  }
}

END {
  few=n/4
  several=n/2
  if (count==0) {print "no occupied zones"}
  else if (count==1) {print "one occupied zone"}
  else if (count<few) {print "few occupied zones"}
  else if (count<=several) {print "several occupied zones"}
  else if (count<n) {print "most occupied zones"}
  else if (count==n) {print "all occupied zones"}
  else {print "ERROR"}  
}
