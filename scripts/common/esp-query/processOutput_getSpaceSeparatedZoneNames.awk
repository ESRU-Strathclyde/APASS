BEGIN {
  FS="="
}

{
  if ($1=="zone_names") {
    gsub(/,/," ",$2)
    print $2
    exit
  }
}
