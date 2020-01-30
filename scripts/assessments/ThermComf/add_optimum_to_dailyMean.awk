BEGIN {
  first=1
  # default number of header lines: 0
  if (nhead=="") {nhead=0}
  # default number of data lines: 2
  if (ndata=="") {ndata=2}
  # default optimum start value: 0.0
  if (optimumS=="") {optimumS=1.0}
  # default optimum finish value: 0.0
  if (optimumF=="") {optimumF=1.0}
  ORS=" "
  OFS=" "
}

{
  l++
  if (l<=nhead) {next}
  ld++
  optimum=optimumS+((optimumF-optimumS)*((ld-1)/(ndata-1)))
  print($1,optimum)
	for (i=2;i<=NF;i++) {print($i)}
  print("\n")
}