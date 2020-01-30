BEGIN {
  FS="="
}

{
  if ($1=="afn_network") { 
    print $2
    exit
  }
}
