BEGIN {
  FS="="
}

{
  if ($1=="rad_scene") { 
    print $2
    exit
  }
}
