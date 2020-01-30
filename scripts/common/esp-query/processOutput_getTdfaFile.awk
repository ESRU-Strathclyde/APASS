BEGIN {
  FS="="
}

{
  if ($1=="tdfa_file") { 
    print $2
    exit
  }
}
