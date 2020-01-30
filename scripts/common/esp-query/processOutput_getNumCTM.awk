BEGIN {
  FS="="
}

{
  if ($1=="number_ctm") { 
    print $2
    exit
  }
}
