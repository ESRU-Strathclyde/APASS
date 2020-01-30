BEGIN {
  FS="="
}

{
  if ($1=="model_description") { 
    print $2
    exit
  }
}
