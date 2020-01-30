BEGIN {
  FS="="
}

{ 
  if ($1=="number_zones") {
    print $2
    exit
  }
}
