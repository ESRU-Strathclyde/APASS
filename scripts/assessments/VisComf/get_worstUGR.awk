{
  for (i=1;i<=NF;i++) {
    if ($i=="-" || $i=="x") {continue}
    if ($i>worst) {
      worst=$i
      worst_vp=i
    }
  }
}

END {
  print worst,worst_vp
}
