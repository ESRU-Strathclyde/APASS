BEGIN {
  ORS=" "
}

{
	if ($1=="view=") {print $2}
}