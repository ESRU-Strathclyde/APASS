{
  if (substr($1,1,1)=="#") {next}
  print $1
  exit
}
