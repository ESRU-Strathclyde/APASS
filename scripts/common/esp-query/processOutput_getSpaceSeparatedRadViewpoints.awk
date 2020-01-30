BEGIN {
  FS="="
}

{
  if ($1=="rad_viewpoints") {
    gsub(/,/," ",$2)
    print $2
    exit
  }
}
