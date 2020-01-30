# This script takes column data from ESP-r, and checks all columns (except the
# first) against upper and lower criteria, printing out column data of the same
# dimensions that consists of positive or negative deviation from the criteria,
# an "x" if there is no discomfort, or a "-" for no result (e.g. not occupied
# in data filtered by occupancy).

BEGIN {
# default upper criterion for deviation: 1
  if (criteriaU=="") {criteriaU=1}
# default lower criterion for deviation: 0
  if (criteriaL=="") {criteriaL=0}

  ORS=" "
}

{
  if (substr($1,1,1)=="#") {next}
  for (i=2;i<=NF;i++) {
    if ($i ~ /^-?[0-9]+\.?[0-9]*$/) {
      n=$i

      # Check upper criterion.
      dif=n-criteriaU
      if (dif>0) {
        print dif
      }
      else {

        # Check lower criterion.
        dif=criteriaL-n
        if (dif>0) {
          print -dif
        }
        else {

          # No discomfort.
          print "x"
        }
      }
    }
    else {
      if ($i=="not" || $i=="no" || $i=="invl") {i++}
      print "-"
    }
  }
  print "\n"
}
