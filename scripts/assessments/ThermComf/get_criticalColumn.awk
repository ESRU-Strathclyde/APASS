BEGIN {
  worst=0
}

{
  for (i=1;i<=NF;i++) {
    if ($i ~ /^-?[0-9]+\.?[0-9]*$/) {
      abs=sqrt($i^2)
      if (abs>worst) {
        worst=abs
        worstZone=i
      }
    }
  }
}

END {
  print worstZone,worst
}
