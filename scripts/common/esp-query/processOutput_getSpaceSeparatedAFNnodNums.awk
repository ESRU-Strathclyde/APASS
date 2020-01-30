BEGIN {
  FS="="
}

{
  if ($1=="afn_zon_nod_nums") {
    gsub(/,/," ",$2)
    print $2
    exit
  }
}
