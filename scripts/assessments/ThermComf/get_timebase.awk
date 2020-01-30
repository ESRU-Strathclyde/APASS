{
  if (substr($1,1,1)=="#") {next}
  print int($1)
  exit
}
