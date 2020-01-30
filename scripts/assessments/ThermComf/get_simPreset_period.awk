BEGIN {
  # Default mode = new simulation preset.
  if ( mode == "" ) mode=2
}

{
  if ( mode == 1 ) {
    if ( $5 == preset ) {
      print $1,$2,$3,$4
      exit
    }
  }
  else if ( mode == 2 ) {
    if ( $10 == preset ) {
      print $6,$7,$8,$9
      exit
    }    
  }
}
