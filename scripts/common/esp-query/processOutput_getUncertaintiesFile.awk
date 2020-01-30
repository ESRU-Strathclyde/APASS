BEGIN {
  FS="="
}

{
  if ($1=="uncertainties_file") { 
    print $2
    exit
  }
}
