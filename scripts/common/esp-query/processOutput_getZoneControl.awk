BEGIN {
  FS="="
}

{ 
  if ($1=="zone_control") {
    print $2
    exit
  }
}
