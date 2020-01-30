BEGIN {
  FS="="
}

{
  if ($1=="ctm_network") { 
    print $2
    exit
  }
}
