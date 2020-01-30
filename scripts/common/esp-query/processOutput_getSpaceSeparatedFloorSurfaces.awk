BEGIN {
  FS="="
}

{
  if ($1=="zone_floor_surfs") {
    gsub(/,/," ",$2)
    print $2
    exit
  }
}
