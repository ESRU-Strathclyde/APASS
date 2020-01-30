BEGIN {
  FS="="
}

{
  if ($1=="model_name") { 
    print $2
    exit
  }
}
