# This script takes column data from ESP-r, and checks all columns (except the
# first) against upper and lower criteria, printing out column data of the same
# dimensions that consists of positive or negative deviation from the criteria,
# an "x" if there is no discomfort, or a "-" for no result (e.g. not occupied
# in data filtered by occupancy).

# In this version, comfort criteria vary linearly over the period between two 
# values.

BEGIN {
# default number of header lines: 0
  if (nhead=="") {nhead=0}
# default number of data lines: 2
  if (ndata=="") {ndata=2}
# default upper criterion start: 1
  if (criteriaUS=="") {criteriaUS=1}
# default upper criterion finish: 1
  if (criteriaUF=="") {criteriaUF=1}
# default lower criterion start: 0
  if (criteriaLS=="") {criteriaLS=0}
# default lower criterion finish: 0
  if (criteriaLF=="") {criteriaLF=0}

  ORS=" "
  l=0
  ld=0
}

{
  l++
  if (l<=nhead) {next}
  if (substr($1,1,1)=="#") {next}

  # Calculate criteria.
  ld++
  criteriaU=criteriaUS+((criteriaUF-criteriaUS)*((ld-1)/(ndata-1)))
  criteriaL=criteriaLS+((criteriaLF-criteriaLS)*((ld-1)/(ndata-1)))

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
