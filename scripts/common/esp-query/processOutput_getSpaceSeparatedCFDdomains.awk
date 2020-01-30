BEGIN {
  FS="="
}

{
  if ($1=="CFD_domains") {
    gsub(/,/," ",$2)
    print $2
    exit
  }
}
