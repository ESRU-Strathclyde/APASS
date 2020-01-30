BEGIN {
  FS="="
}

{
  if ($1=="MRT_sensors") {
    gsub(/,/," ",$2)
    print $2
    exit
  }
}
