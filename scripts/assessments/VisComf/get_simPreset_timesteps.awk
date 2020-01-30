BEGIN {
  # Default mode = new simulation preset.
  if ( mode == "" ) mode=2
}

{
  if ( mode == 1 ) {
    if ( $1 == "*sps" ) {
      print $4
      exit
    }
  }
  else if ( mode == 2 ) {
    if ( $10 == preset ) {
      print $2
      exit
    }
  }
}
