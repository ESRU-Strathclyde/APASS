# Outputs:
# -1: not occupied
# 0: compliant
# 1: non-compliant

BEGIN {
  ORS=" "
}

{
  for (i=1;i<=NF;i++) {
  	if ($i=="not_occ") {print -1}    
    else if ($i==0) {print 0}
    else {print 1}
  }
}

END {
  print "\n"
}
